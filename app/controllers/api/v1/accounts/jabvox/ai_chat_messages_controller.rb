# rubocop:disable Metrics/ClassLength
class Api::V1::Accounts::Jabvox::AiChatMessagesController < Api::V1::Accounts::BaseController
  include ActionController::Live
  include JabvoxChatTurnPersistence
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

  def sessions # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    # El historial del Chat IA es PRIVADO POR USUARIO: cada usuario ve solo SUS chats, no los de
    # otros usuarios de la cuenta. La lectura filtra por account_id + user_id.
    #
    # Incluye metadata para poder mostrar a qué AGENTE/conexión pertenece cada sesión y
    # asegurar que solo ese agente la atienda (el front bloquea el cambio de agente).
    sessions_data = JabvoxAiChatMessage
                    .where(account_id: Current.account.id, user_id: current_user.id)
                    .select(:session_id_jabvox, :created_at, :metadata_jabvox)
                    .order(created_at: :asc)

    grouped = sessions_data.each_with_object({}) do |m, h|
      sid = m.session_id_jabvox
      h[sid] ||= { session_id: sid, created_at: m.created_at, last_message_at: m.created_at,
                   connection_id: nil, agent: nil, title: nil }
      h[sid][:last_message_at] = m.created_at if m.created_at > h[sid][:last_message_at]
      # El agente/conexión de la sesión = el primero registrado en metadata.
      meta = m.metadata_jabvox || {}
      if h[sid][:connection_id].nil? && meta['connection_id'].present?
        h[sid][:connection_id] = meta['connection_id']
        h[sid][:agent] = meta['agent']
      end
    end

    # Título de cada sesión desde la tabla nueva (privada por usuario). Si no hay fila/título,
    # queda nil y el front sigue mostrando "Sesión N".
    titles = JabvoxAiChatSession.for_account(Current.account.id)
                                .where(user_id: current_user.id, session_id_jabvox: grouped.keys)
                                .pluck(:session_id_jabvox, :title_jabvox).to_h
    grouped.each { |sid, s| s[:title] = titles[sid].presence }

    render json: grouped.values.sort_by { |s| s[:last_message_at] }.reverse
  end

  def index
    session_id = params[:session_id]
    page = (params[:page] || 1).to_i
    per = 50

    # LECTURA privada por usuario (ver nota en #sessions): account_id + user_id.
    scope = JabvoxAiChatMessage
            .where(account_id: Current.account.id, user_id: current_user.id, session_id_jabvox: session_id)

    # Mostrar los mensajes RECIENTES, no los 50 más antiguos: se toman los N últimos por
    # created_at descendente (página N-ésima desde el final) y se re-ordenan ascendente para
    # render. Así una sesión con >50 mensajes abre en lo último, no en lo más viejo.
    messages = scope
               .order(created_at: :desc)
               .offset((page - 1) * per)
               .limit(per)
               .to_a
               .reverse

    render json: messages.map { |m| message_json(m) }
  end

  def create # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/AbcSize
    check_access!
    return if performed?

    check_open_chats_limit!
    return if performed?

    session_id = params[:session_id].presence || SecureRandom.uuid
    mode = params[:mode].presence&.in?(%w[model documents]) ? params[:mode] : 'model'

    model_record = find_model(params[:model_id])
    raise 'No hay ningún modelo de IA configurado para esta cuenta.' unless model_record

    # Historial privado por usuario (ver nota en #sessions): account + user + session.
    history = JabvoxAiChatMessage
              .where(account: Current.account, user: current_user, session_id_jabvox: session_id)
              .order(:created_at)
              .last(20)

    service = Jabvox::AiChatService.new(account: Current.account, user: current_user, model_record: model_record)
    response_text = service.send_message(content: params[:content], session_id: session_id, mode: mode, history: history)

    # Crea la fila de sesión (con auto-título) al primer mensaje del usuario de esta sesión.
    ensure_session_record(session_id)
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

    # account_id DEBE ir dentro de data: el front valida data.account_id en isAValidEvent;
    # fuera de data el evento se descarta en silencio (regla ActionCable de Jabvox).
    ActionCable.server.broadcast(current_user.pubsub_token, {
                                   event: 'jabvox.ai_chat.response_created',
                                   data: { account_id: Current.account.id, session_id: session_id,
                                           message: message_json(assistant_msg) }
                                 })

    render json: { session_id: session_id, message: message_json(assistant_msg) }, status: :created
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Chat en STREAMING (SSE) — reenvía en vivo lo que hace el agente Hermes (texto + tools),
  # igual que Telegram. Solo aplica a modelos Hermes (source='hermes'); para otros, error.
  def stream # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    check_access!
    return if performed?

    session_id = params[:session_id].presence || SecureRandom.uuid
    conn = find_hermes_connection
    return unless hermes_connection_ready?(conn)

    set_sse_headers
    # Anuncia al cliente el session_id REAL de Jabvox nada más abrir el stream. En un chat nuevo
    # el cliente usó un id "pending_<ts>" temporal; con esto lo ADOPTA (re-clava los mensajes al
    # UUID real), así salir durante/justo tras el primer turno no "pierde" la sesión.
    write_sse("event: jabvox.session\ndata: #{{ session_id: session_id }.to_json}\n\n")
    # Guarda el mensaje del usuario ANTES de empezar (así no se pierde si sale del módulo).
    # Cada sesión queda ligada a la conexión/agente que la atiende (conn.id).
    persist_user_message(session_id, conn)
    # El texto se acumula en @stream_full y las tools en @stream_tools MIENTRAS llega el
    # stream, para que la persistencia del ensure vea siempre lo último aunque el turno se
    # corte (el usuario pulsó Stop / salió del módulo → el navegador aborta el HTTP y este
    # request puede terminar sin volver de stream_via_connection). Por eso la persistencia
    # va en el ensure y es idempotente (@persisted evita duplicar cuando termina normal).
    @stream_full = +''
    @stream_tools = []
    @stream_ctx = { session_id: session_id, conn: conn }
    # La fila del asistente se crea YA (vacía, 'streaming'): a partir de aquí el turno existe
    # en BD aunque el cliente cierre o el proceso muera, así el historial nunca queda mudo.
    start_assistant_turn!(session_id: session_id, conn: conn)
    # El texto y las tools se acumulan DENTRO del stream (on_chunk), no con el valor de
    # retorno, para no perder lo parcial si el cliente aborta a mitad. No re-sumamos aquí.
    stream_via_connection(conn, session_id)
    persist_stream_result!
  rescue StandardError => e
    Rails.logger.warn("[AiChatStream] #{e.class}: #{e.message}")
    @stream_failed = true
    write_sse("data: #{{ error: e.message }.to_json}\n\n")
  ensure
    # Persiste SIEMPRE, incluso si el cliente abortó el HTTP (Stop) y no volvimos del stream.
    persist_stream_result!
    begin
      response.stream.close
    rescue IOError
      nil
    end
  end

  # Guarda el mensaje del asistente una sola vez (idempotente) con el texto y las tools
  # acumulados hasta el momento. Se llama en el flujo normal y de nuevo en el ensure: la
  # bandera @persisted garantiza un único INSERT aunque el turno se cortara a mitad.
  def persist_stream_result!
    return if @persisted || @stream_ctx.blank?

    @persisted = true
    # NUNCA se descarta el turno: aunque venga vacío se cierra con su estado, que es lo que
    # permite ver al volver si se interrumpió o si terminó sin responder.
    status = if @stream_failed
               JabvoxChatTurnPersistence::STATUS_FAILED
             elsif @stream_full.to_s.strip.empty? && @stream_tools.blank?
               JabvoxChatTurnPersistence::STATUS_INTERRUPTED
             else
               JabvoxChatTurnPersistence::STATUS_COMPLETED
             end
    finish_assistant_turn!(@stream_full.to_s, tools: @stream_tools.presence, status: status)
  rescue StandardError => e
    Rails.logger.warn("[AiChatStream] persist failed: #{e.class}: #{e.message}")
  end

  def destroy
    # Historial privado por usuario: se borra por (cuenta, usuario, session_id), para que cada
    # usuario solo pueda eliminar SUS propios chats IA, no los de otros usuarios de la cuenta.
    JabvoxAiChatMessage.where(
      account_id: Current.account.id,
      user_id: current_user.id,
      session_id_jabvox: params[:id]
    ).destroy_all
    JabvoxAiChatSession.for_account(Current.account.id)
                       .where(user_id: current_user.id, session_id_jabvox: params[:id]).destroy_all
    head :ok
  end

  # Renombra una sesión (privada por usuario). Recibe session_id (:id) + title. Crea la fila
  # de sesión si aún no existe (sesión virtual previa a la tabla nueva). Scoped a cuenta + usuario.
  def rename
    session_id = params[:id].to_s
    title = params[:title].to_s.strip
    return render(json: { error: 'session_id requerido' }, status: :unprocessable_entity) if session_id.blank?
    return render(json: { error: 'El título no puede estar vacío.' }, status: :unprocessable_entity) if title.blank?
    return render(json: { error: 'El título es demasiado largo.' }, status: :unprocessable_entity) if title.length > 255

    session = JabvoxAiChatSession.find_or_initialize_by(
      account_id: Current.account.id, user_id: current_user.id, session_id_jabvox: session_id
    )
    session.title_jabvox = title
    session.save!
    render json: { session_id: session_id, title: session.title_jabvox }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Ruta set_model existía sin implementación (404). El Chat IA ya elige modelo/proveedor por
  # mensaje (llm_overrides en el stream) y por el comando "/model" que Hermes interpreta, así
  # que no hay estado de modelo que persistir por sesión en Jabvox. Se responde OK idempotente
  # para no romper al cliente que la invoque; el modelo efectivo lo fija el stream/comando.
  def set_model
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

    render(json: { error: 'No tienes un agente de Manty asignado para chatear.' },
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
    # Historial privado por usuario (ver nota en #sessions): account + user + session.
    history = JabvoxAiChatMessage
              .where(account: Current.account, user: current_user, session_id_jabvox: session_id)
              .order(:created_at).last(20)
    messages = history.map { |m| { role: m.role_jabvox, content: m.content_jabvox } }
    messages << { role: 'user', content: user_content_with_attachments }

    client = Jabvox::Hermes::SessionsClient.new(
      base_url: conn.base_url_jabvox, token: conn.token_jabvox,
      model: conn.hermes_agent_name_jabvox
    )
    # Reenvía cada frame al navegador Y, en el MISMO callback: acumula las tools y el texto
    # parcial en @stream_tools/@stream_full. Así, si el usuario pulsa Stop (el navegador
    # aborta el HTTP a mitad), lo ya recibido queda guardado por el ensure. `llm_overrides`
    # lleva el modelo/proveedor elegidos en el picker (nil = default del agente).
    client.chat_stream(messages, llm_overrides: llm_overrides, on_chunk: lambda { |chunk|
      capture_tool_frame(chunk)
      @stream_full << extract_delta_text(chunk) if @stream_full
      # Vuelca el parcial cada tanto: si el turno se corta aquí, lo recibido queda en BD.
      flush_assistant_turn(@stream_full, tools: @stream_tools.presence)
      write_sse(chunk)
    })
  end

  # Extrae el texto (choices[].delta.content) de un chunk SSE para acumular la respuesta
  # parcial en el propio controlador. Robusto: ignora frames no-JSON, [DONE] y eventos de
  # tool. Espeja extract_stream_text del SessionsClient (aquí se necesita por-chunk para
  # persistir lo parcial si el usuario corta el stream).
  def extract_delta_text(chunk)
    out = +''
    chunk.to_s.each_line do |line|
      next unless line.start_with?('data:')

      data = line.sub('data:', '').strip
      next if data.empty? || data == '[DONE]'

      begin
        out << JSON.parse(data).dig('choices', 0, 'delta', 'content').to_s
      rescue JSON::ParserError
        next
      end
    end
    out
  end

  # Modelo/proveedor LLM elegidos por el usuario en el picker (params), validados a strings
  # simples. nil cuando no se envían → Hermes usa el default del agente.
  def llm_overrides
    model = params[:llm_model].to_s.strip
    provider = params[:llm_provider].to_s.strip
    out = {}
    out[:model] = model if model.present? && model.length <= 100
    out[:provider] = provider if provider.present? && provider.length <= 50
    out.presence
  end

  # Detecta frames SSE "event: hermes.tool.progress\ndata: {json}" y acumula la tool en
  # @stream_tools (dedup por id, quedándose con el último estado de cada tool). Recorre las
  # líneas: cuando ve el event de tool, parsea la siguiente línea data: como la herramienta.
  def capture_tool_frame(chunk)
    return unless chunk.to_s.include?('hermes.tool.progress')

    in_tool_event = false
    chunk.to_s.each_line do |line|
      stripped = line.strip
      if stripped.start_with?('event:')
        in_tool_event = stripped.include?('hermes.tool.progress')
      elsif in_tool_event && stripped.start_with?('data:')
        record_tool(stripped.sub(/\Adata:\s*/, ''))
        in_tool_event = false
      end
    end
  end

  # Acumula/actualiza una herramienta del turno. Hermes emite DOS frames por tool con el
  # mismo identificador: 'running' (trae tool/emoji/label = el comando) y 'completed' (solo
  # status, SIN label ni emoji). Por eso: (1) el dedup es por toolCallId (con id como
  # fallback), no por 'id' — que Hermes no envía; y (2) se MERGEA en vez de reemplazar, para
  # no perder el comando/emoji cuando llega el 'completed'. Espeja upsertTool del frontend.
  def record_tool(json_str) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return if json_str.blank?

    tool = JSON.parse(json_str)
    return unless tool.is_a?(Hash)

    key = tool['toolCallId'] || tool['id'] || tool['tool']
    return if key.blank?

    idx = @stream_tools.index { |t| (t['toolCallId'] || t['id'] || t['tool']) == key }
    if idx
      @stream_tools[idx] = @stream_tools[idx].merge(tool.compact)
    else
      @stream_tools << tool
    end
  rescue JSON::ParserError => e
    Rails.logger.debug { "[AiChatStream] tool frame parse skipped: #{e.message}" }
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

  def persist_user_message(session_id, conn = nil)
    # Crea la fila de sesión (con auto-título) al primer mensaje del usuario de esta sesión.
    ensure_session_record(session_id, conn)
    JabvoxAiChatMessage.create!(
      account: Current.account, user: current_user, session_id_jabvox: session_id,
      role_jabvox: 'user', content_jabvox: params[:content],
      # Ata la sesión a su conexión/agente: quién la atiende no cambia después.
      metadata_jabvox: conn ? { connection_id: conn.id, agent: conn.name_jabvox } : {}
    )
  end

  # Asegura la fila JabvoxAiChatSession de esta sesión (privada por usuario). Al crearla por
  # primera vez, AUTO-TÍTULO con las primeras ~50 chars del primer mensaje del usuario (o el
  # título explícito pasado en params[:title], p. ej. desde "/new <nombre>"). find_or_create_by
  # + rescue sobre el índice único evita duplicar en accesos concurrentes. Idempotente: si ya
  # existe (y ya tiene título), no lo pisa.
  def ensure_session_record(session_id, conn = nil)
    return if session_id.blank?

    JabvoxAiChatSession.find_or_create_by!(
      account_id: Current.account.id, user_id: current_user.id, session_id_jabvox: session_id
    ) do |s|
      s.connection_id = conn&.id
      s.title_jabvox = requested_title.presence || JabvoxAiChatSession.auto_title_from(params[:content])
    end
    # Si la sesión existía sin título (sesión virtual previa) y ahora llega un título explícito,
    # lo adopta sin pisar un auto-título ya puesto.

  rescue ActiveRecord::RecordNotUnique
    JabvoxAiChatSession.for_account(Current.account.id).find_by(user_id: current_user.id, session_id_jabvox: session_id)
  rescue StandardError => e
    Rails.logger.warn("[AiChat] ensure_session_record falló: #{e.class}: #{e.message}")
    nil
  end

  # Título explícito pasado por el cliente (p. ej. "/new <nombre>"), saneado a string corto.
  def requested_title
    t = params[:title].to_s.strip
    t.present? && t.length <= 255 ? t : nil
  end

  # Guarda la respuesta del asistente al terminar (o al cortarse) el stream, incluyendo las
  # herramientas ejecutadas (para que reaparezcan al reabrir el chat). No guarda si no hubo
  # ni texto ni tools (turno vacío).
  # Nombres de columna que usa JabvoxChatTurnPersistence (difieren del chat aprovisionador).
  def content_column = :content_jabvox
  def metadata_column = :metadata_jabvox

  # Crea la fila del asistente del turno en curso (vacía, estado 'streaming').
  def build_assistant_message(status:, content:, session_id:, conn: nil)
    metadata = {}
    metadata[:agent] = conn.name_jabvox if conn.respond_to?(:name_jabvox)
    metadata[:connection_id] = conn.id if conn.respond_to?(:id)
    JabvoxAiChatMessage.create!(
      account: Current.account, user: current_user, session_id_jabvox: session_id,
      role_jabvox: 'assistant', content_jabvox: content.presence || '…',
      status_jabvox: status, metadata_jabvox: metadata
    )
  end

  def persist_assistant_message(session_id, conn, full_text, tools = [])
    text = full_text.to_s
    return if text.strip.empty? && tools.blank?

    metadata = { agent: conn.respond_to?(:name_jabvox) ? conn.name_jabvox : conn.to_s }
    metadata[:connection_id] = conn.id if conn.respond_to?(:id)
    metadata[:tools] = tools if tools.present?
    # content_jabvox valida presence: si el turno fue SOLO herramientas (o el usuario cortó
    # antes del texto), guardamos un marcador para no perder el mensaje ni sus tools.
    content = text.strip.empty? ? '_(herramientas ejecutadas)_' : text
    JabvoxAiChatMessage.create!(
      account: Current.account, user: current_user, session_id_jabvox: session_id,
      role_jabvox: 'assistant', content_jabvox: content,
      metadata_jabvox: metadata
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
      status: m.status_jabvox, created_at: m.created_at, updated_at: m.updated_at }
  end
end
# rubocop:enable Metrics/ClassLength
