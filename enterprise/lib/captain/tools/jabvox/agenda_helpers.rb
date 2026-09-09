# frozen_string_literal: true

# Helpers compartidos por las tools de agenda y tareas de Jabvox IA
# (agendar cita, consultar disponibilidad, crear tarea). Resuelven, desde el
# `state` de la conversación, el agente responsable, el lead/contacto y la zona
# horaria, de forma consistente y siempre scoped por cuenta.
module Captain::Tools::Jabvox::AgendaHelpers
  private

  # Zona horaria efectiva: la del inbox de la conversación (viene en el state) o UTC.
  def resolved_timezone(state)
    state[:timezone].presence || 'UTC'
  end

  # Agente responsable por defecto: el asignado a la conversación actual. Si la
  # conversación no tiene asignado, no adivinamos: devolvemos nil y la tool
  # informa al asistente para que pida a quién asignar.
  def default_agent(state)
    conversation = find_conversation(state)
    conversation&.assignee
  end

  # Resuelve un agente por id validando que pertenezca a la cuenta. Sin id, cae
  # al agente por defecto (asignado de la conversación).
  def resolve_agent(state, user_id)
    if user_id.present?
      account_scoped_users.find_by(id: user_id)
    else
      default_agent(state)
    end
  end

  def account_scoped_users
    @assistant.account.users
  end

  # Lead de Jabvox del contacto de la conversación (uno por contacto y cuenta).
  # Puede ser nil si el contacto aún no tiene lead; las tareas lo aceptan opcional.
  def conversation_lead(state)
    contact_id = state&.dig(:contact, :id)
    return nil unless contact_id

    JabvoxLead.find_by(account_id: @assistant.account_id, contact_id: contact_id)
  end

  # Fecha/hora que aceptamos del LLM: ISO 8601 con fecha completa (YYYY-MM-DD),
  # opcionalmente con hora. Exigimos esta forma para NO caer en el parseo
  # permisivo de Time.parse, que extrae una fecha de texto libre como "el martes
  # que viene" y agendaría en una fecha absurda.
  ISO_DATETIME = /\A\d{4}-\d{2}-\d{2}([ T]\d{2}:\d{2}(:\d{2})?)?/

  # Parsea una fecha/hora ISO 8601 a la zona dada. Devuelve nil si el texto no
  # tiene forma de fecha ISO o no es una fecha válida.
  def parse_time(value, timezone)
    return nil if value.blank?
    return nil unless value.to_s.strip.match?(ISO_DATETIME)

    tz = ActiveSupport::TimeZone[timezone] || ActiveSupport::TimeZone['UTC']
    tz.parse(value.to_s.strip)
  rescue ArgumentError, TypeError
    nil
  end

  def format_slot(slot, timezone)
    tz = ActiveSupport::TimeZone[timezone] || ActiveSupport::TimeZone['UTC']
    start_at = slot[:start_at].in_time_zone(tz)
    end_at = slot[:end_at].in_time_zone(tz)
    "#{start_at.strftime('%Y-%m-%d %H:%M')} - #{end_at.strftime('%H:%M')}"
  end
end
