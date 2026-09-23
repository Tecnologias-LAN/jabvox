# frozen_string_literal: true

# Persistencia del turno del asistente en los chats (IA y Aprovisionador).
#
# El problema que resuelve: antes el mensaje del asistente se escribía UNA sola vez, al final,
# y solo si había texto o herramientas:
#
#     return if text.strip.empty? && tools.blank?
#
# Si el usuario salía del chat mientras el agente trabajaba, o el turno quedaba esperando una
# aprobación, no se guardaba nada y la respuesta desaparecía del historial.
#
# Ahora el mensaje se CREA al empezar el turno (status 'streaming') y se va actualizando con
# lo que llega. Así, pase lo que pase — el navegador corta, el worker muere, el turno espera
# aprobación — siempre queda una fila que dice en qué estado quedó y con el texto recibido
# hasta ese momento.
module JabvoxChatTurnPersistence
  extend ActiveSupport::Concern

  # Cada cuántos caracteres nuevos se vuelca el parcial a BD. Sin esto habría un UPDATE por
  # token; con esto, uno cada párrafo aproximadamente.
  FLUSH_EVERY_CHARS = 400
  # Y cada cuánto como máximo, para que un turno lento (una herramienta larga) también guarde.
  FLUSH_EVERY_SECONDS = 5

  STATUS_STREAMING = 'streaming'
  STATUS_WAITING_APPROVAL = 'waiting_approval'
  STATUS_COMPLETED = 'completed'
  STATUS_INTERRUPTED = 'interrupted'
  STATUS_FAILED = 'failed'

  private

  # Crea la fila del asistente en cuanto arranca el turno. A partir de aquí el mensaje existe
  # en BD aunque todo lo demás falle.
  def start_assistant_turn!(**attrs)
    @turn_record = build_assistant_message(status: STATUS_STREAMING, content: '', **attrs)
    @turn_flushed_at = Time.current
    @turn_flushed_len = 0
    # Se reinicia por si la misma instancia atiende otro turno: un @turn_finished heredado
    # haría que el cierre del turno nuevo se ignorara en silencio.
    @turn_finished = false
    @turn_record
  rescue StandardError => e
    Rails.logger.warn("[ChatTurn] no se pudo crear el turno: #{e.class}: #{e.message}")
    nil
  end

  # Vuelca el texto parcial si ya toca (por tamaño o por tiempo). Se llama desde on_chunk.
  def flush_assistant_turn(text, tools: nil, force: false)
    return if @turn_record.nil?

    grown = text.to_s.length - @turn_flushed_len.to_i
    aged = Time.current - @turn_flushed_at.to_time
    return unless force || grown >= FLUSH_EVERY_CHARS || aged >= FLUSH_EVERY_SECONDS

    write_turn(text, tools: tools)
  rescue StandardError => e
    Rails.logger.warn("[ChatTurn] flush falló: #{e.class}: #{e.message}")
  end

  # El agente se detuvo a pedir permiso: se deja constancia para que al volver al chat el
  # operador vea que hay algo pendiente suyo y no una conversación muda.
  def mark_turn_waiting_approval(text, approval: nil)
    return if @turn_record.nil?

    write_turn(text, status: STATUS_WAITING_APPROVAL, extra_metadata: { approval: approval }.compact)
  rescue StandardError => e
    Rails.logger.warn("[ChatTurn] waiting_approval falló: #{e.class}: #{e.message}")
  end

  # Cierre del turno. `interrupted` cuando el cliente cortó antes de que el agente terminara:
  # el texto parcial SÍ se conserva, solo cambia el estado.
  def finish_assistant_turn!(text, tools: nil, status: STATUS_COMPLETED, extra_metadata: nil)
    return if @turn_record.nil? || @turn_finished

    @turn_finished = true
    final = text.to_s
    # Un turno sin texto pero con herramientas sigue siendo información útil; y uno sin nada
    # se marca igualmente para que el historial refleje que ocurrió.
    content = final.strip.presence || turn_placeholder(tools, status, extra_metadata)
    write_turn(content, tools: tools, status: status, extra_metadata: extra_metadata)
  rescue StandardError => e
    Rails.logger.warn("[ChatTurn] cierre falló: #{e.class}: #{e.message}")
  end

  STATUS_PLACEHOLDERS = {
    STATUS_INTERRUPTED => '_(el turno se interrumpió antes de responder)_',
    STATUS_WAITING_APPROVAL => '_(esperando autorización)_',
    STATUS_FAILED => '_(el turno falló)_'
  }.freeze

  # Texto que ve el usuario cuando el turno no produjo respuesta. Nunca se deja vacío: el
  # motivo es justo lo que necesita saber al volver al chat.
  def turn_placeholder(tools, status, extra_metadata = nil)
    error = metadata_error(extra_metadata)
    return "_(el turno falló: #{error})_" if error.present?
    return '_(herramientas ejecutadas)_' if tools.present?

    STATUS_PLACEHOLDERS.fetch(status, '_(sin respuesta)_')
  end

  def metadata_error(extra_metadata)
    return nil unless extra_metadata.is_a?(Hash)

    extra_metadata[:error] || extra_metadata['error']
  end

  # Se usa update_columns (no update!) a propósito: este método corre en mitad del stream,
  # varias veces por turno, y solo toca columnas ya validadas al crear la fila. Saltarse
  # validaciones y callbacks evita trabajo por chunk; el estado se valida en el modelo cuando
  # la fila nace y los valores posibles son constantes del propio concern.
  # rubocop:disable Rails/SkipsModelValidations
  def write_turn(text, tools: nil, status: nil, extra_metadata: nil)
    attrs = { content_column => text.to_s }
    attrs[:status_jabvox] = status if status
    meta = @turn_record.public_send(metadata_column) || {}
    meta = meta.merge('tools' => tools) if tools.present?
    meta = meta.merge(extra_metadata.stringify_keys) if extra_metadata.present?
    attrs[metadata_column] = meta
    @turn_record.update_columns(attrs.merge(updated_at: Time.current))
    @turn_flushed_at = Time.current
    @turn_flushed_len = text.to_s.length
  end
  # rubocop:enable Rails/SkipsModelValidations
end
