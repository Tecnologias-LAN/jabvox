# frozen_string_literal: true

# Parseo de los frames SSE que llegan del aprovisionador mientras corre un turno.
#
# Del stream se extraen tres cosas, además de reenviarlo tal cual al navegador:
#   - el texto (delta.content) para persistir la respuesta aunque el cliente cierre;
#   - las herramientas ejecutadas (hermes.tool.progress), dedup por toolCallId;
#   - el run_id y la sesión de Hermes, sin los cuales no se pueden responder aprobaciones,
#     hacer steer ni fijar el modelo en turnos posteriores.
module JabvoxProvisioningChatStreamFrames
  extend ActiveSupport::Concern

  private

  # Captura run_id / session_id de cualquier frame que los traiga (el evento `run` inicial y
  # los eventos del propio run).
  def capture_run_frame(chunk)
    text = chunk.to_s
    return unless text.include?('run_id') || text.include?('session_id')

    text.each_line do |line|
      s = line.strip
      next unless s.start_with?('data:')

      absorb_run_ids(parse_sse_data(s))
    end
  end

  def parse_sse_data(line)
    JSON.parse(line.delete_prefix('data:').strip)
  rescue JSON::ParserError
    nil
  end

  # Sigue en qué estado va el turno para poder guardarlo: si el agente pidió aprobación, si ya
  # la resolvió, y si el run llegó a terminar. Sin esto, al volver al chat no habría forma de
  # distinguir "se cortó a medias" de "quedó esperando tu autorización".
  def capture_turn_state(chunk)
    text = chunk.to_s
    return unless text.include?('approval') || text.include?('run.')

    if text.include?('approval.request')
      @awaiting_approval = true
      # Se guarda de inmediato (force) para que la solicitud sobreviva aunque el cliente
      # cierre el navegador justo después.
      mark_turn_waiting_approval(@stream_full.to_s, approval: extract_approval(text))
    end
    @awaiting_approval = false if text.include?('approval.responded')
    @run_completed = true if text.include?('run.completed')
    # Un run que falla del lado de Hermes (modelo no disponible, error del proveedor) debe
    # quedar como 'failed', no como 'completed': si no, el historial diría que el turno
    # terminó bien cuando en realidad no hubo respuesta.
    return unless text.include?('run.failed')

    @stream_failed = true
    @run_error = extract_run_error(text)
  end

  # Mensaje de error del run, para guardarlo con el turno y que el usuario sepa qué pasó.
  def extract_run_error(text)
    text.each_line do |line|
      next unless line.strip.start_with?('data:')

      data = parse_sse_data(line.strip)
      next unless data.is_a?(Hash) && data['event'] == 'run.failed'

      return data['error'].to_s.first(300).presence
    end
    nil
  end

  def extract_approval(text)
    text.each_line do |line|
      next unless line.strip.start_with?('data:')

      data = parse_sse_data(line.strip)
      next unless data.is_a?(Hash) && data['event'] == 'approval.request'

      return data.slice('command', 'description', 'choices', 'request_id', 'run_id')
    end
    nil
  end

  def absorb_run_ids(data)
    return unless data.is_a?(Hash)

    @run_id = data['run_id'] if data['run_id'].present?
    @hermes_session_id = data['session_id'] if data['session_id'].present?
  end

  # Acumula las herramientas ejecutadas en @stream_tools (dedup por toolCallId, merge para no
  # perder el comando).
  #
  # Hay DOS formatos según el transporte, y se soportan los dos:
  #   - chat clásico: "event: hermes.tool.progress\ndata: {json}" (el tipo va en la línea SSE)
  #   - API de runs:  "data: {\"event\": \"tool.started\", ...}" (el tipo va DENTRO del JSON)
  TOOL_EVENTS = %w[hermes.tool.progress tool.started tool.completed tool.failed].freeze

  def capture_tool_frame(chunk)
    text = chunk.to_s
    return unless TOOL_EVENTS.any? { |e| text.include?(e) }

    in_tool = false
    text.each_line do |line|
      s = line.strip
      if s.start_with?('event:')
        in_tool = TOOL_EVENTS.any? { |e| s.include?(e) }
      elsif s.start_with?('data:')
        record_tool_line(s, in_tool)
        in_tool = false
      end
    end
  end

  # Guarda la tool si el frame lo es: porque la línea `event:` anterior lo anunció, o porque
  # el propio JSON declara un evento de herramienta.
  def record_tool_line(line, announced)
    payload = line.delete_prefix('data:').strip
    return if payload.blank?

    data = parse_sse_data("data:#{payload}")
    return unless data.is_a?(Hash)
    return unless announced || TOOL_EVENTS.include?(data['event'].to_s)

    record_tool_hash(data)
  end

  def record_tool_hash(tool)
    key = tool_key(tool)
    return if key.blank?

    idx = @stream_tools.index { |t| tool_key(t) == key }
    idx ? @stream_tools[idx] = @stream_tools[idx].merge(tool.compact) : @stream_tools << tool
  end

  def tool_key(tool)
    tool['toolCallId'] || tool['id'] || tool['tool']
  end

  # Extrae el texto de un chunk SSE para acumular la respuesta y poder persistirla aunque el
  # cliente cierre. Dos formatos: el run manda {"event":"message.delta","delta":"..."} y el
  # chat clásico {"choices":[{"delta":{"content":"..."}}]}.
  def extract_delta_text(chunk)
    out = +''
    chunk.to_s.each_line do |line|
      next unless line.start_with?('data:')

      data = line.delete_prefix('data:').strip
      next if data.empty? || data == '[DONE]'

      out << frame_text(parse_sse_data("data:#{data}"))
    end
    out
  end

  # `message.interim` son borradores que el agente reescribe: se descartan para no duplicar
  # el texto final.
  def frame_text(parsed)
    return '' unless parsed.is_a?(Hash)
    return '' if parsed['event'].to_s == 'message.interim'

    (parsed['delta'] || parsed.dig('choices', 0, 'delta', 'content')).to_s
  end
end
