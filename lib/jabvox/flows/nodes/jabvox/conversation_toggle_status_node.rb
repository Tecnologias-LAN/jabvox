# frozen_string_literal: true

# jabvox.conversation.toggle_status — cambia el estado de la conversación.
#
# EL BUG QUE ESTE NODO NO PUEDE REINTRODUCIR: por HTTP la fecha de "pospuesta"
# se parseaba con strptime('%s'), o sea que EXIGÍA un timestamp Unix; una fecha
# legible se guardaba en silencio como 1970-01-01 y la conversación se reabría
# al instante. Aquí se aceptan ambos formatos y una fecha ilegible FALLA.
class Jabvox::Flows::Nodes::Jabvox::ConversationToggleStatusNode < Jabvox::Flows::Nodes::Jabvox::Base
  type 'jabvox.conversation.toggle_status'
  label 'Cambiar estado de conversación'

  STATUSES = Conversation.statuses.keys.freeze

  def perform
    conversation = find_conversation!(param(:conversationId))
    status = read_status
    snoozed_until = status == 'snoozed' ? read_snoozed_until : nil
    conversation.update!(status: status, snoozed_until: snoozed_until)
    output(conversation)
  end

  private

  def read_status
    value = first_filled(param(:status), 'resolved')
    return value if STATUSES.include?(value)

    fail_with!("\"#{value}\" no es un estado válido. Usa uno de: #{STATUSES.join(', ')}.")
  end

  # Vacío = pospuesta indefinidamente. Se acepta timestamp Unix en segundos o
  # cualquier fecha legible (ISO, "2026-08-01 09:00"…).
  def read_snoozed_until
    raw = first_filled(param(:snoozedUntil))
    return nil if raw.blank?

    parse_time(raw) || fail_with!(unparseable_message(raw))
  end

  # `Time.zone.parse` es tan permisivo que de "el martes que viene" saca una
  # fecha inventada: se exige antes una fecha AAAA-MM-DD o DD/MM/AAAA real.
  DATE_SHAPE = %r{\A\s*(\d{4}-\d{1,2}-\d{1,2}|\d{1,2}/\d{1,2}/\d{4})([T\s].*)?\z}

  def parse_time(raw)
    return Time.zone.at(Integer(raw, 10)) if raw.match?(/\A\d+\z/)
    return nil unless raw.match?(DATE_SHAPE)

    Time.zone.parse(raw)
  rescue ArgumentError, TypeError
    nil
  end

  def unparseable_message(raw)
    "No se entiende la fecha de \"Posponer hasta\": «#{raw}». Escribe una fecha legible " \
      '(p.ej. 2026-08-01 09:00 o 2026-08-01T09:00:00Z) o un timestamp Unix en segundos. ' \
      'Déjalo vacío para posponer indefinidamente.'
  end

  def output(conversation)
    { 'conversationId' => conversation.display_id, 'status' => conversation.status,
      'snoozed_until' => conversation.snoozed_until&.iso8601,
      'assignee_id' => conversation.assignee_id, 'team_id' => conversation.team_id }
  end
end
