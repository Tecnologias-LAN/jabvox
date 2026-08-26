# rubocop:disable Metrics/ClassLength
class Api::V1::Accounts::Jabvox::AiChatMessagesController < Api::V1::Accounts::BaseController
  include ActionController::Live
  include JabvoxPermissions

  before_action :check_feature_enabled

  def my_access
    can_manage = jabvox_can?('jabvox_ai_chat_manage')
    render json: {
      can_use: jabvox_can?('jabvox_ai_chat_use'),
      can_use_models: can_manage,
      can_use_documents: can_manage
    }
  end

  def sessions
    sessions_data = JabvoxAiChatMessage
                    .where(account_id: Current.account.id, user_id: current_user.id)
                    .select(:session_id_jabvox, :created_at)
                    .group(:session_id_jabvox, :created_at)
                    .order(created_at: :asc)

    grouped = sessions_data.each_with_object({}) do |m, h|
      sid = m.session_id_jabvox
      h[sid] ||= { session_id: sid, created_at: m.created_at, last_message_at: m.created_at }
      h[sid][:last_message_at] = m.created_at if m.created_at > h[sid][:last_message_at]
    end

    render json: grouped.values.sort_by { |s| s[:last_message_at] }.reverse
  end

  def index
    session_id = params[:session_id]
    page = (params[:page] || 1).to_i
    per = 50

    messages = JabvoxAiChatMessage
               .where(account_id: Current.account.id, user_id: current_user.id, session_id_jabvox: session_id)
               .order(created_at: :asc)
               .offset((page - 1) * per)
               .limit(per)

    render json: messages.map { |m| message_json(m) }
  end

  def create
    check_access!
    return if performed?

    check_open_chats_limit!
    return if performed?

    session_id = params[:session_id].presence || SecureRandom.uuid
    mode = params[:mode].presence&.in?(%w[model documents]) ? params[:mode] : 'model'

    model_record = find_model(params[:model_id])
    raise 'No hay ningún modelo de IA configurado para esta cuenta.' unless model_record

    history = JabvoxAiChatMessage
              .where(account: Current.account, user: current_user, session_id_jabvox: session_id)
              .order(:created_at)
              .last(20)

    service = Jabvox::AiChatService.new(account: Current.account, user: current_user, model_record: model_record)
    response_text = service.send_message(content: params[:content], session_id: session_id, mode: mode, history: history)

    JabvoxAiChatMessage.create!(
      account: Current.account, user: current_user,
      session_id_jabvox: session_id, role_jabvox: 'user', content_jabvox: params[:content],
      metadata_jabvox: { mode: mode }
    )
    assistant_msg = JabvoxAiChatMessage.create!(
      account: Current.account, user: current_user,
      session_id_jabvox: session_id, role_jabvox: 'assistant', content_jabvox: response_text,
      metadata_jabvox: { mode: mode, model: model_record.model_jabvox }
    )

    ActionCable.server.broadcast(current_user.pubsub_token, {
                                   event: 'jabvox.ai_chat.response_created',
                                   account_id: Current.account.id,
                                   data: { session_id: session_id, message: message_json(assistant_msg) }
                                 })

    render json: { session_id: session_id, message: message_json(assistant_msg) }, status: :created
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Chat en STREAMING (SSE) — reenvía en vivo lo que hace el agente Hermes (texto + tools),
  # igual que Telegram. Solo aplica a modelos Hermes (source='hermes'); para otros, error.
  def stream
    check_access!
    return if performed?

    session_id = params[:session_id].presence || SecureRandom.uuid
    conn = find_hermes_connection
    return unless hermes_connection_ready?(conn)

    set_sse_headers
    # Guarda el mensaje del usuario ANTES de empezar (así no se pierde si sale del módulo).
    persist_user_message(session_id)
    # La respuesta se acumula y se PERSISTE al final SIEMPRE, aunque el cliente cierre la
    # conexión (sale del módulo): el turno de Hermes se completa igual y queda guardado, así
    # al volver el usuario ve el avance/resultado.
    full = stream_via_connection(conn, session_id)
    persist_assistant_message(session_id, conn.hermes_agent_name_jabvox, full)
  rescue StandardError => e
    Rails.logger.warn("[AiChatStream] #{e.class}: #{e.message}")
    write_sse("data: #{{ error: e.message }.to_json}\n\n")
  ensure
    begin
      response.stream.close
    rescue IOError
      nil
    end
  end

  def destroy
    JabvoxAiChatMessage.where(
      account_id: Current.account.id,
      user_id: current_user.id,
      session_id_jabvox: params[:id]
    ).destroy_all
    head :ok
  end

  private

  # Conexión Hermes que el usuario eligió (por connection_id), o su primera conexión ligada.
  def find_hermes_connection
    agent = Current.account.jabvox_hermes_agents.find_by(user_id: current_user.id)
    return nil unless agent

    if params[:connection_id].present?
      agent.hermes_connections.find_by(id: params[:connection_id])
    else
      agent.hermes_connections.order(:name_jabvox).first
    end
  end

  def hermes_connection_ready?(conn)
    return true if conn.present?

    render(json: { error: 'No tienes un agente de Hermes asignado para chatear.' },
           status: :unprocessable_entity)
    false
  end

  def set_sse_headers
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['X-Accel-Buffering'] = 'no'
  end

  # Abre el stream al agente Hermes elegido y reenvía cada frame SSE al navegador.
  def stream_via_connection(conn, session_id)
    history = JabvoxAiChatMessage
              .where(account: Current.account, user: current_user, session_id_jabvox: session_id)
              .order(:created_at).last(20)
    messages = history.map { |m| { role: m.role_jabvox, content: m.content_jabvox } }
    messages << { role: 'user', content: user_content_with_attachments }

    client = Jabvox::Hermes::SessionsClient.new(
      base_url: conn.base_url_jabvox, token: conn.token_jabvox,
      model: conn.hermes_agent_name_jabvox
    )
    client.chat_stream(messages, on_chunk: ->(chunk) { write_sse(chunk) })
  end

  # Construye el content del mensaje: texto + imágenes (vision) + URLs de docs/audios.
  # `attachments`: [{ type: 'image'|'file', url:, name: }]. Imágenes → image_url (data o http);
  # documentos/audios → se referencian por URL en el texto para que Hermes los descargue.
  def user_content_with_attachments
    atts = attachment_list.select { |a| a['url'].present? }
    return params[:content].to_s if atts.empty?

    text = params[:content].to_s + file_refs_text(atts)
    images = atts.select { |a| a['type'].to_s == 'image' }
    return text if images.empty?

    [{ type: 'text', text: text }] + images.map { |img| image_part(img) }
  end

  # Documentos/audios: se referencian por URL para que Hermes los descargue.
  def file_refs_text(atts)
    atts.reject { |a| a['type'].to_s == 'image' }
        .map { |f| "\n\n[Archivo adjunto: #{f['name']} → #{f['url']}]" }.join
  end

  def image_part(img)
    { type: 'image_url', image_url: { url: img['url'] } }
  end

  # attachments como array de hashes con claves string (tolerante a ActionController::Parameters).
  def attachment_list
    raw = params[:attachments]
    return [] if raw.blank?

    Array(raw).map { |a| a.respond_to?(:to_unsafe_h) ? a.to_unsafe_h.stringify_keys : a.stringify_keys }
  end

  def write_sse(chunk)
    response.stream.write(chunk)
  rescue IOError
    nil # el cliente cerró la conexión (el agente se interrumpe solo)
  end

  def persist_user_message(session_id)
    JabvoxAiChatMessage.create!(
      account: Current.account, user: current_user, session_id_jabvox: session_id,
      role_jabvox: 'user', content_jabvox: params[:content], metadata_jabvox: {}
    )
  end

  # Guarda la respuesta del asistente al terminar (o al cortarse) el stream.
  def persist_assistant_message(session_id, agent_name, full_text)
    return if full_text.to_s.strip.empty?

    JabvoxAiChatMessage.create!(
      account: Current.account, user: current_user, session_id_jabvox: session_id,
      role_jabvox: 'assistant', content_jabvox: full_text,
      metadata_jabvox: { agent: agent_name }
    )
  end

  def check_feature_enabled
    render json: { error: 'Chat IA no está habilitado para esta cuenta.' }, status: :forbidden unless Current.account.jabvox_ai_chat_enabled_jabvox
  end

  def check_access!
    return if jabvox_can?('jabvox_ai_chat_use')

    render json: { error: 'No tienes acceso al Chat IA.' }, status: :forbidden
  end

  def check_open_chats_limit!
    max = Current.account.jabvox_ai_chat_max_open_chats_jabvox
    return unless max.positive?

    count = JabvoxAiChatMessage
            .where(account_id: Current.account.id, user_id: current_user.id)
            .distinct.count(:session_id_jabvox)
    return unless count >= max
    return if params[:session_id].present?

    render json: { error: "Has alcanzado el límite de #{max} conversaciones abiertas." }, status: :unprocessable_entity
  end

  def find_model(model_id)
    if model_id.present?
      Current.account.jabvox_ai_chat_models.find_by(id: model_id)
    else
      JabvoxAiChatModel.default_for(Current.account.id) ||
        Current.account.jabvox_ai_chat_models.first
    end
  end

  def message_json(m)
    { id: m.id, session_id: m.session_id_jabvox, role: m.role_jabvox, content: m.content_jabvox, metadata: m.metadata_jabvox,
      created_at: m.created_at }
  end
end
# rubocop:enable Metrics/ClassLength
