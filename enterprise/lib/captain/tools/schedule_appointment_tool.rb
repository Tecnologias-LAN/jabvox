# frozen_string_literal: true

# Tool nativa de Jabvox IA: agenda una cita en el calendario de Jabvox. Crea un
# evento tipo "appointment" asignado al agente responsable y vinculado al
# contacto/lead de la conversación actual. Reutiliza Jabvox::CalendarEventBuilder.
class Captain::Tools::ScheduleAppointmentTool < Captain::Tools::BasePublicTool
  include Captain::Tools::Jabvox::AgendaHelpers

  DEFAULT_DURATION_MIN = 30

  description 'Agenda una cita en el calendario para el cliente de esta ' \
              'conversación. Indica la fecha y hora de inicio (formato ISO, p. ej. ' \
              '2026-09-15T15:00). Antes de agendar, verifica la disponibilidad del ' \
              'agente con la herramienta de consultar disponibilidad.'

  param :inicio, type: 'string',
                 desc: 'Fecha y hora de inicio en ISO 8601, p. ej. "2026-09-15T15:00".'
  param :motivo, type: 'string', required: false,
                 desc: 'Motivo de la cita (para qué es), p. ej. "Limpieza dental", ' \
                       '"Control de ortodoncia". Se guarda en la descripción de la cita.'
  param :titulo, type: 'string', required: false,
                 desc: 'Título de la cita. Si se omite, se genera con el motivo y el nombre del cliente.'
  param :duracion_min, type: 'integer', required: false,
                       desc: "Duración en minutos (por defecto #{DEFAULT_DURATION_MIN})."
  param :nota, type: 'string', required: false,
               desc: 'Nota adicional para el agente (detalles, referencias).'
  param :agente_id, type: 'integer', required: false,
                    desc: 'ID del agente responsable. Si se omite, el asignado a la conversación.'

  def perform(tool_context, inicio:, motivo: nil, titulo: nil, duracion_min: nil, nota: nil, agente_id: nil)
    state = tool_context.state
    timezone = resolved_timezone(state)

    agent = resolve_agent(state, agente_id)
    return sin_agente_msg if agent.nil?

    start_at = parse_time(inicio, timezone)
    return "No entendí la fecha/hora \"#{inicio}\". Usa formato ISO, p. ej. 2026-09-15T15:00." if start_at.nil?
    return 'La fecha de la cita ya pasó. Propón una fecha futura.' if start_at <= Time.current

    end_at = start_at + slot_duration(duracion_min).minutes
    contact = find_contact(state)
    details = { motivo: motivo, titulo: titulo, nota: nota }
    event = reserve_slot!(agent, contact, start_at, end_at, details)
    return cita_ocupada_msg(agent, timezone) if event.nil?

    log_tool_usage('agendar_cita', { event_id: event.id, agente_id: agent.id, contact_id: contact&.id })
    cita_confirmada_msg(agent, contact, start_at, end_at, timezone)
  rescue ActiveRecord::RecordInvalid => e
    "No se pudo agendar la cita: #{e.record.errors.full_messages.to_sentence}"
  end

  private

  # Namespace del advisory lock (constante arbitraria, distinta de otros locks
  # de la app) para serializar las reservas por agente.
  LOCK_NAMESPACE = 84_217

  # Comprueba el solape y crea la cita dentro de UNA transacción con advisory
  # lock por agente, de modo que dos peticiones concurrentes para el mismo agente
  # no puedan reservar el mismo hueco (evita el doble booking). Devuelve el evento
  # creado, o nil si el hueco ya estaba ocupado.
  def reserve_slot!(agent, contact, start_at, end_at, details)
    ActiveRecord::Base.transaction do
      ActiveRecord::Base.connection.execute(
        "SELECT pg_advisory_xact_lock(#{LOCK_NAMESPACE}, #{agent.id.to_i})"
      )
      if solapa_cita_existente?(agent, start_at, end_at)
        nil
      else
        build_event(agent, contact, start_at, end_at, details)
      end
    end
  end

  def cita_confirmada_msg(agent, contact, start_at, end_at, timezone)
    "Cita agendada para #{format_slot({ start_at: start_at, end_at: end_at }, timezone)} " \
      "con #{agent.name}#{contact ? " y #{contact.name}" : ''}."
  end

  def slot_duration(duracion_min)
    (duracion_min.presence || DEFAULT_DURATION_MIN).to_i.clamp(5, 8 * 60)
  end

  def build_event(agent, contact, start_at, end_at, details)
    Jabvox::CalendarEventBuilder.new(
      account: @assistant.account,
      user: agent,
      attributes: {
        title: details[:titulo].presence || titulo_por_defecto(contact, details[:motivo]),
        description: descripcion_cita(agent, contact, details),
        note: details[:nota],
        event_type: :appointment,
        status: :pending,
        contact_id: contact&.id
      },
      slots: [{ start_at: start_at, end_at: end_at, all_day: false }]
    ).perform!.first
  end

  # Descripción completa: motivo, datos de contacto del paciente/lead, agente
  # responsable y quién la agendó, para que el agente asignado tenga el contexto.
  def descripcion_cita(agent, contact, details)
    lines = []
    lines << "Motivo: #{details[:motivo]}" if details[:motivo].present?
    if contact
      lines << "Cliente: #{contact.name}"
      lines << "Teléfono: #{contact.phone_number}" if contact.phone_number.present?
      lines << "Email: #{contact.email}" if contact.email.present?
    end
    lines << "Agente responsable: #{agent.name}"
    lines << "Agendada por: #{@assistant.name} (Jabvox IA)"
    lines << details[:nota] if details[:nota].present?
    lines.join("\n")
  end

  def solapa_cita_existente?(agent, start_at, end_at)
    @assistant.account.jabvox_calendar_events
              .for_user(agent.id)
              .where.not(status: :cancelled)
              .exists?(['start_at < ? AND end_at > ?', end_at, start_at])
  end

  def titulo_por_defecto(contact, motivo = nil)
    base = motivo.presence || 'Cita'
    contact ? "#{base} - #{contact.name}" : "#{base} (agendada por Jabvox IA)"
  end

  def cita_ocupada_msg(agent, timezone)
    "#{agent.name} ya tiene una cita en ese horario. Consulta la disponibilidad " \
      "(zona #{timezone}) y propón otro hueco."
  end

  def sin_agente_msg
    'No hay un agente asignado a esta conversación. Pregunta con qué agente se ' \
      'debe agendar la cita (indica su ID) antes de continuar.'
  end
end
