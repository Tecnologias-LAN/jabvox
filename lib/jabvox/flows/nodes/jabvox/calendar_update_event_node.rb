# frozen_string_literal: true

# jabvox.calendar.update_event — actualiza SOLO lo configurado. Los participantes
# se reemplazan únicamente si el usuario eligió alguno: la clave presente pero
# vacía vaciaba la lista del evento sin que nadie lo pidiera.
class Jabvox::Flows::Nodes::Jabvox::CalendarUpdateEventNode < Jabvox::Flows::Nodes::Jabvox::CalendarBase
  type 'jabvox.calendar.update_event'
  label 'Actualizar Evento'

  def perform
    event = find_event!(param(:eventId))
    changes = update_attributes
    fail_with!(nothing_to_update_message) if changes.empty? && !participants_configured?

    event.update!(changes) if changes.any?
    sync_participants(event) if participants_configured?
    event_view(event.reload)
  end

  private

  def update_attributes
    text_attributes.merge(time_attributes, enum_attributes, flag_attributes, contact_attribute)
  end

  def text_attributes
    { title: first_filled(param(:title)), description: first_filled(param(:description)),
      note: first_filled(param(:note)), color: first_filled(param(:color)) }
      .reject { |_k, v| v.blank? }
  end

  def time_attributes
    { start_at: parse_time(param(:start), 'la fecha de inicio'),
      end_at: parse_time(param(:end), 'la fecha de fin') }.compact
  end

  def enum_attributes
    { event_type: valid_enum(param(:eventType), EVENT_TYPES, 'el tipo de evento'),
      status: valid_enum(param(:status), EVENT_STATUSES, 'el estado') }.compact
  end

  # Booleanos de tres estados: sin la clave no se tocan, con ella se aplican.
  def flag_attributes
    { all_day: param(:allDay), remind_before_day: param(:remindBeforeDay),
      remind_before_hour: param(:remindBeforeHour) }
      .reject { |_k, v| blank_param?(v) }
      .transform_values { |v| opt_in?(v) }
  end

  def contact_attribute
    raw = first_filled(param(:contactId))
    raw.blank? ? {} : { contact_id: find_contact!(raw).id }
  end

  def sync_participants(event)
    event.jabvox_calendar_event_participants.destroy_all
    participant_attrs.each do |attrs|
      event.jabvox_calendar_event_participants.create!(
        user_id: attrs[:user_id],
        jabvox_calendar_external_person_id: attrs[:external_person_id],
        note: event.note
      )
    end
  end

  def nothing_to_update_message
    'No se configuró ningún campo que actualizar en el evento. Rellena al menos uno ' \
      '(título, fechas, tipo, estado, contacto o participantes).'
  end
end
