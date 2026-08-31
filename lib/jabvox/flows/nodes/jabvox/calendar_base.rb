# frozen_string_literal: true

# Base común de los nodos `jabvox.calendar.*`: resuelve el evento, el dueño, las
# fechas y los participantes SIEMPRE dentro de la cuenta del run.
class Jabvox::Flows::Nodes::Jabvox::CalendarBase < Jabvox::Flows::Nodes::Jabvox::Base
  EVENT_TYPES = %w[reminder appointment task].freeze
  EVENT_STATUSES = %w[pending done cancelled].freeze

  private

  def find_event!(raw, label = 'el ID del evento')
    event_id = require_id!(raw, label)
    event = account.jabvox_calendar_events.find_by(id: event_id)
    return event if event

    fail_with!("El evento #{event_id} no existe en esta cuenta (puede haberse borrado). " \
               'Comprueba el ID del evento en el paso.')
  end

  # El evento CUELGA de un usuario (user_id es obligatorio en el modelo). Un run
  # no tiene sesión, así que se usa el primer ADMINISTRADOR de la cuenta.
  def event_owner!
    owner = account.administrators.order(:id).first
    return owner if owner

    fail_with!('Esta cuenta no tiene ningún administrador al que asignar el evento. ' \
               'Todo evento de calendario necesita un usuario dueño: crea un administrador.')
  end

  def valid_enum(raw, allowed, label, fallback = nil)
    value = first_filled(raw)
    return fallback if value.blank?
    return value if allowed.include?(value)

    fail_with!("Valor no válido para #{label}: \"#{value}\". Valores admitidos: #{allowed.join(', ')}.")
  end

  # Fecha del evento. Si no se puede leer se FALLA: guardar nil dejaba el evento
  # sin fecha y sin aviso.
  def parse_time(raw, label)
    text = first_filled(raw)
    return nil if text.blank?

    Time.zone.parse(text) || fail_with!(bad_date_message(text, label))
  rescue ArgumentError, TypeError
    fail_with!(bad_date_message(text, label))
  end

  def bad_date_message(raw, label)
    "No se entiende #{label}: \"#{raw}\". Usa un formato como 2026-08-01 o 2026-08-01 09:00."
  end

  # Participantes desde los DOS multiselect del catálogo. Se validan dentro de
  # la cuenta: un id ajeno colgaría el evento de gente de otro tenant.
  def participant_attrs
    users = verified_ids(str_list(param(:attendeeUserIds)), account.users, 'agentes')
    people = verified_ids(str_list(param(:attendeeExternalIds)), account.jabvox_calendar_external_people,
                          'personas externas del calendario')
    users.map { |id| { user_id: id } } + people.map { |id| { external_person_id: id } }
  end

  # ¿Se configuró algún participante? Distingue "no tocar" de "lista vacía": la
  # clave presente vaciaba la lista existente del evento.
  def participants_configured?
    str_list(param(:attendeeUserIds)).any? || str_list(param(:attendeeExternalIds)).any?
  end

  def verified_ids(raw, scope, label)
    wanted = raw.map(&:to_i).uniq.reject(&:zero?)
    return [] if wanted.empty?

    missing = wanted - scope.where(id: wanted).pluck(:id)
    if missing.any?
      fail_with!("Estos #{label} no pertenecen a esta cuenta: #{missing.join(', ')}. " \
                 'Elige participantes de la lista.')
    end

    wanted
  end

  def event_view(event)
    { 'id' => event.id, 'eventId' => event.id, 'title' => event.title,
      'description' => event.description, 'note' => event.note,
      'start_at' => event.start_at&.iso8601, 'end_at' => event.end_at&.iso8601,
      'all_day' => event.all_day, 'event_type' => event.event_type, 'status' => event.status,
      'color' => event.color, 'contact_id' => event.contact_id, 'user_id' => event.user_id,
      'remind_before_day' => event.remind_before_day, 'remind_before_hour' => event.remind_before_hour,
      'participants' => event.jabvox_calendar_event_participants.map { |p| participant_view(p) } }
  end

  def participant_view(participant)
    { 'id' => participant.id, 'user_id' => participant.user_id,
      'external_person_id' => participant.jabvox_calendar_external_person_id,
      'name' => participant.display_name, 'email' => participant.email,
      'kind' => participant.team_member? ? 'team' : 'external' }
  end
end
