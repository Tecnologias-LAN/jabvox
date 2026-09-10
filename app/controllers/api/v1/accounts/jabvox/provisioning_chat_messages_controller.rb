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

  jabvox_feature 'jabvox_ai_chat_provisioning'
  # Todas las acciones exigen el permiso de gestión (crear MCPs es una acción sensible).
  before_action -> { jabvox_authorize!('jabvox_ai_chat_provisioning_manage') }

  def index
    msgs = Current.account.jabvox_provisioning_chat_messages.chronological.limit(200)
    render json: msgs.map { |m| serialize(m) }
  end

  def create
    content = params[:content].to_s.strip
    return render(json: { error: 'content requerido' }, status: :unprocessable_entity) if content.blank?

    persist('user', content)
    result = Jabvox::ProvisioningChatService.new(
      account: Current.account, user: Current.user
    ).handle(content)
    assistant = persist('assistant', result[:reply], metadata: result[:metadata] || {})
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
    persist('user', content) # se guarda antes: no se pierde si sale del módulo
    @stream_full = +''
    @stream_tools = []
    @stream_started = true
    run_provisioner_stream(content)
    persist_assistant_stream!
  rescue StandardError => e
    Rails.logger.warn("[ProvisioningChatStream] #{e.class}: #{e.message}")
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
  def run_provisioner_stream(content)
    relay = Jabvox::Hermes::ProvisionerChatRelay.new(account: Current.account, user: Current.user)
    relay.stream_message(content, on_chunk: lambda { |chunk|
      capture_tool_frame(chunk)
      @stream_full << extract_delta_text(chunk) if @stream_full
      write_sse(chunk)
    })
  end

  # Persiste el mensaje del asistente UNA sola vez (idempotente) con el texto y tools
  # acumulados. Se llama en el flujo normal y en el ensure: @persisted evita duplicar.
  def persist_assistant_stream! # rubocop:disable Metrics/CyclomaticComplexity
    return if @persisted || !@stream_started

    @persisted = true
    text = @stream_full.to_s
    return if text.strip.empty? && @stream_tools.blank?

    metadata = { via: 'provisioner' }
    metadata[:tools] = @stream_tools if @stream_tools.present?
    content = text.strip.empty? ? '_(herramientas ejecutadas)_' : text
    persist('assistant', content, metadata: metadata)
  rescue StandardError => e
    Rails.logger.warn("[ProvisioningChatStream] persist failed: #{e.class}: #{e.message}")
  end

  # Detecta frames "event: hermes.tool.progress\ndata: {json}" y acumula la tool en
  # @stream_tools (dedup por toolCallId, merge para no perder el comando). Igual que el Chat IA.
  def capture_tool_frame(chunk)
    return unless chunk.to_s.include?('hermes.tool.progress')

    in_tool = false
    chunk.to_s.each_line do |line|
      s = line.strip
      if s.start_with?('event:')
        in_tool = s.include?('hermes.tool.progress')
      elsif in_tool && s.start_with?('data:')
        record_tool(s.sub(/\Adata:\s*/, ''))
        in_tool = false
      end
    end
  end

  def record_tool(json_str) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    return if json_str.blank?

    tool = JSON.parse(json_str)
    return unless tool.is_a?(Hash)

    key = tool['toolCallId'] || tool['id'] || tool['tool']
    return if key.blank?

    idx = @stream_tools.index { |t| (t['toolCallId'] || t['id'] || t['tool']) == key }
    idx ? @stream_tools[idx] = @stream_tools[idx].merge(tool.compact) : @stream_tools << tool
  rescue JSON::ParserError
    nil
  end

  # Extrae el texto (choices[].delta.content) de un chunk SSE para acumular la respuesta.
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

  def write_sse(chunk)
    response.stream.write(chunk)
  rescue IOError
    nil # el cliente cerró la conexión
  end

  def persist(role, content, metadata: {})
    Current.account.jabvox_provisioning_chat_messages.create!(
      user: Current.user, role: role, content: content, metadata: metadata
    )
  end

  def serialize(msg)
    { id: msg.id, role: msg.role, content: msg.content, metadata: msg.metadata,
      created_at: msg.created_at }
  end
end
