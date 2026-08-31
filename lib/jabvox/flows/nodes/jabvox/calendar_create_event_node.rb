# frozen_string_literal: true

# jabvox.calendar.create_event — crea un evento en el calendario de la cuenta.
# `end_at` es OBLIGATORIO en el modelo: sin fin se asume +1 h (o el día completo).
class Jabvox::Flows::Nodes::Jabvox::CalendarCreateEventNode < Jabvox::Flows::Nodes::Jabvox::CalendarBase
  type 'jabvox.calendar.create_event'
  label 'Crear Evento'

  def perform
    event = account.jabvox_calendar_events.new(create_attributes)
    event.user = event_owner!
    event.save!
    attach_participants(event)
    event_view(event.reload)
  end

  private

  def create_attributes
    start_at = start_time
    { title: title, description: first_filled(param(:description)).presence,
      note: first_filled(param(:note)).presence,
      start_at: start_at, end_at: end_time(start_at), all_day: all_day,
      event_type: valid_enum(param(:eventType), EVENT_TYPES, 'el tipo de evento', 'reminder'),
      status: valid_enum(param(:status), EVENT_STATUSES, 'el estado', 'pending'),
      contact_id: linked_contact&.id,
      remind_before_day: opt_in?(param(:remindBeforeDay)),
      remind_before_hour: opt_in?(param(:remindBeforeHour)) }.merge(color_attribute)
  end

  # El color solo se manda si se configuró: vacío deja el default del modelo.
  def color_attribute
    color = first_filled(param(:color))
    color.blank? ? {} : { color: color }
  end

  def title
    text = first_filled(param(:title))
    fail_with!('Falta el título del evento: es obligatorio para crearlo.') if text.blank?

    text
  end

  def all_day
    opt_in?(param(:allDay))
  end

  def start_time
    parse_time(param(:start), 'la fecha de inicio') ||
      fail_with!('Falta la fecha de inicio del evento: es obligatoria. Usa 2026-08-01 o 2026-08-01 09:00.')
  end

  # Sin fin explícito se deriva del inicio: todo el día → +24 h; si no → +1 h.
  def end_time(start_at)
    parse_time(param(:end), 'la fecha de fin') || (start_at + (all_day ? 24 : 1).hours)
  end

  def linked_contact
    raw = first_filled(param(:contactId))
    raw.present? ? find_contact!(raw) : nil
  end

  def attach_participants(event)
    participant_attrs.each do |attrs|
      event.jabvox_calendar_event_participants.create!(
        user_id: attrs[:user_id],
        jabvox_calendar_external_person_id: attrs[:external_person_id],
        note: event.note
      )
    end
  end
end
