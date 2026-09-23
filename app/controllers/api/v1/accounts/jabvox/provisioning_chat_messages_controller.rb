# frozen_string_literal: true

# Chat Aprovisionamiento de UNA cuenta: el usuario (con permiso) le pide al Hermes
# Provisioner de su cuenta crear/aprovisionar MCPs. Gateado por el módulo
# jabvox_ai_chat_provisioning Y por el permiso de usuario jabvox_ai_chat_provisioning_manage.
#
# AISLAMIENTO: todo ocurre dentro de Current.account; nunca se toca otra cuenta. El
# aprovisionamiento crea/usa SOLO el handoff (team+MCPs+virtual server+token) de esta cuenta.
#
#   GET  .../provisioning_chat_messages          → historial de esta cuenta
#   POST .../provisioning_chat_messages          → { content } → respuesta del Provisioner
#   GET  .../provisioning_chat_messages/status    → estado del handoff (sin token)
#   POST .../provisioning_chat_messages/provision → aprovisionamiento inicial (idempotente)
class Api::V1::Accounts::Jabvox::ProvisioningChatMessagesController < Api::V1::Accounts::Jabvox::BaseController
  include ActionController::Live
  include JabvoxPermissions
  include JabvoxProvisioningChatSessions
  include JabvoxProvisioningChatRunControl
  include JabvoxProvisioningChatStreamFrames
  include JabvoxChatTurnPersistence

  jabvox_feature 'jabvox_ai_chat_provisioning'
  # Todas las acciones exigen el permiso de gestión (crear MCPs es una acción sensible).
  before_action -> { jabvox_authorize!('jabvox_ai_chat_provisioning_manage') }

  # Mensajes de UNA conversación. Sin session_id devuelve la más reciente, para que al
  # entrar al chat se vea la última conversación en vez de todo mezclado.
  def index
    sid = params[:session_id].presence || latest_session_id
    return render(json: []) if sid.blank?

    msgs = Current.account.jabvox_provisioning_chat_messages.in_session(sid).chronological.limit(200)
    render json: msgs.map { |m| serialize(m) }
  end

  # Lista de conversaciones para la barra lateral.
  def sessions
    render json: JabvoxProvisioningChatMessage.sessions_for(Current.account.id)
  end

  # Modelos que ofrece el aprovisionador, para el picker.
  def model_options
    render json: { data: relay.model_options }
  end

  # Borra una conversación completa de esta cuenta.
  def destroy_session
    sid = params[:session_id].to_s
    return render(json: { error: 'session_id requerido' }, status: :unprocessable_entity) if sid.blank?

    count = Current.account.jabvox_provisioning_chat_messages.in_session(sid).destroy_all.size
    render json: { deleted: count }
  end

  def create
    content = params[:content].to_s.strip
    return render(json: { error: 'content requerido' }, status: :unprocessable_entity) if content.blank?

    sid = resolved_session_id
    persist('user', content, session_id: sid)
    result = Jabvox::ProvisioningChatService.new(
      account: Current.account, user: Current.user
    ).handle(content)
    assistant = persist('assistant', result[:reply], metadata: result[:metadata] || {}, session_id: sid)
    render json: serialize(assistant)
  end

  # Chat en STREAMING (SSE) hacia el Hermes Aprovisionador — igual que el Chat IA de la
  # cuenta. Reenvía en vivo el texto y las herramientas (crear MCP, levantar Hermes…), evita
  # el timeout de la respuesta sync, y PERSISTE siempre el resultado (aunque el cliente cierre
  # o el turno se corte), con las tools capturadas en metadata para que reaparezcan al volver.
  def stream # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    content = params[:content].to_s.strip
    if content.blank?
      set_sse_headers
      write_sse("data: #{{ error: 'content requerido' }.to_json}\n\n")
      return response.stream.close
    end

    set_sse_headers
    @session_id = resolved_session_id
    # El historial se lee ANTES de guardar el mensaje nuevo, para no duplicarlo: el actual
    # se añade aparte en el relay.
    history = session_history(@session_id)
    persist('user', content, session_id: @session_id) # se guarda antes: no se pierde si sale del módulo
    @stream_full = +''
    @stream_tools = []
    @stream_started = true
    # La fila del asistente se crea YA, vacía y en estado 'streaming': a partir de aquí el
    # turno existe en BD aunque el cliente cierre o el proceso muera a mitad.
    start_assistant_turn!(session_id: @session_id)
    # El cliente necesita saber en qué sesión quedó el mensaje (sobre todo si era nueva).
    write_sse("event: session\ndata: #{{ session_id: @session_id }.to_json}\n\n")
    run_provisioner_stream(content, history: history, hermes_session_id: hermes_session_id_for(@session_id))
    persist_assistant_stream!
  rescue StandardError => e
    Rails.logger.warn("[ProvisioningChatStream] #{e.class}: #{e.message}")
    @stream_failed = true
    write_sse("data: #{{ error: e.message }.to_json}\n\n")
  ensure
    persist_assistant_stream! # persiste SIEMPRE, aunque el cliente abortara el HTTP
    begin
      response.stream.close
    rescue IOError
      nil
    end
  end

  # Estado del aprovisionamiento de la cuenta (nunca expone el token).
  def status
    handoff = Current.account.jabvox_context_forge_handoff
    render json: (handoff&.safe_summary || { status: 'pending', mcp_servers: [], has_token: false })
  end

  # Envía al agente Aprovisionador global el mensaje inicial de aprovisionamiento de MCPs de
  # esta cuenta. Jabvox solo transporta el texto (ProvisionerChatRelay); el agente responde en
  # línea. Requiere que la cuenta esté activada (ligada) al aprovisionador.
  def provision
    unless JabvoxHermesProvisionerLink.active_for?(Current.account.id)
      return render(json: { error: 'La cuenta no está ligada a un Hermes Aprovisionador' },
                    status: :unprocessable_entity)
    end

    msg = "Levanta y aprovisiona el Hermes de la cuenta #{Current.account.id} con sus MCPs por defecto."
    result = Jabvox::Hermes::ProvisionerChatRelay.new(account: Current.account, user: Current.user)
                                                 .send_message(msg)
    handoff = Current.account.jabvox_context_forge_handoff
    if result.success?
      render json: (handoff&.safe_summary || { status: 'provisioning' }).merge(reply: result.text)
    else
      render json: { error: result.error, status: handoff&.status || 'pending' },
             status: :unprocessable_entity
    end
  end

  private

  def set_sse_headers
    response.headers['Content-Type'] = 'text/event-stream'
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['X-Accel-Buffering'] = 'no'
  end

  # Abre el stream hacia el aprovisionador y, por cada frame: acumula texto y tools (para
  # persistir lo parcial si el cliente corta) y lo reenvía al navegador.
  def run_provisioner_stream(content, history: [], hermes_session_id: nil)
    relay.stream_message(
      content, history: history, llm_overrides: llm_overrides, session_id: hermes_session_id,
               on_chunk: lambda { |chunk|
                 capture_run_frame(chunk)
                 capture_tool_frame(chunk)
                 capture_turn_state(chunk)
                 @stream_full << extract_delta_text(chunk) if @stream_full
                 # Vuelca el parcial cada tanto: si el turno se corta aquí, lo ya recibido
                 # queda en BD en vez de perderse.
                 flush_assistant_turn(@stream_full, tools: @stream_tools.presence)
                 write_sse(chunk)
               }
    )
  end

  # La sesión de Hermes de esta conversación, para que los turnos compartan contexto del lado
  # del agente y /model tenga a qué sesión aplicarse. Se guarda en la metadata del último
  # mensaje que la conoció.
  def hermes_session_id_for(session_id)
    Current.account.jabvox_provisioning_chat_messages
           .in_session(session_id)
           .where("metadata ->> 'hermes_session_id' IS NOT NULL")
           .recent_first
           .limit(1)
           .pick(Arel.sql("metadata ->> 'hermes_session_id'"))
  end

  # Cierra el turno del asistente (idempotente: @persisted evita repetirlo entre el flujo
  # normal y el ensure). La fila ya existe desde start_assistant_turn!, así que aquí solo se
  # fija el texto final y el estado — NUNCA se descarta el mensaje, ni aunque venga vacío:
  # un turno sin respuesta es justo lo que el usuario necesita ver al volver.
  def persist_assistant_stream!
    return if @persisted || !@stream_started

    @persisted = true
    finish_assistant_turn!(@stream_full.to_s, tools: @stream_tools.presence,
                                              status: final_turn_status, extra_metadata: { error: @run_error }.compact)
  rescue StandardError => e
    Rails.logger.warn("[ProvisioningChatStream] persist failed: #{e.class}: #{e.message}")
  end

  # Cómo terminó el turno: esperando aprobación (el agente pidió permiso y nadie respondió
  # todavía), fallido, interrumpido (el cliente cortó sin que llegara el fin del run) o
  # completado.
  def final_turn_status
    return JabvoxChatTurnPersistence::STATUS_WAITING_APPROVAL if @awaiting_approval
    return JabvoxChatTurnPersistence::STATUS_FAILED if @stream_failed
    return JabvoxChatTurnPersistence::STATUS_INTERRUPTED unless @run_completed || @stream_full.to_s.strip.present?

    JabvoxChatTurnPersistence::STATUS_COMPLETED
  end

  # run_id y sesión de Hermes se guardan con el mensaje: sin ellos no se pueden responder
  # aprobaciones, hacer steer ni fijar el modelo en turnos posteriores.
  def stream_metadata
    {
      via: 'provisioner',
      tools: @stream_tools.presence,
      run_id: @run_id.presence,
      hermes_session_id: @hermes_session_id.presence,
      # Si el run falló del lado de Hermes, el motivo viaja con el turno para que el usuario
      # vea por qué no hubo respuesta en vez de un mensaje vacío.
      error: @run_error.presence
    }.compact
  end

  def write_sse(chunk)
    response.stream.write(chunk)
  rescue IOError
    nil # el cliente cerró la conexión
  end

  # Nombres de columna que usa JabvoxChatTurnPersistence (difieren entre los dos chats).
  def content_column = :content
  def metadata_column = :metadata

  # Crea la fila del asistente del turno en curso.
  def build_assistant_message(status:, content:, session_id:)
    Current.account.jabvox_provisioning_chat_messages.create!(
      user: Current.user, role: 'assistant', content: content.presence || '…',
      session_id: session_id, status_jabvox: status, metadata: stream_metadata
    )
  end

  def persist(role, content, metadata: {}, session_id: nil)
    Current.account.jabvox_provisioning_chat_messages.create!(
      user: Current.user, role: role, content: content, metadata: metadata,
      session_id: session_id || @session_id || resolved_session_id
    )
  end

  def serialize(msg)
    { id: msg.id, role: msg.role, content: msg.content, metadata: msg.metadata,
      session_id: msg.session_id, status: msg.status_jabvox, created_at: msg.created_at,
      updated_at: msg.updated_at }
  end
end
