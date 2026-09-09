# frozen_string_literal: true

# Tool nativa de Jabvox IA: devuelve los huecos libres de un agente en los
# próximos días, para que el asistente pueda ofrecer horarios de cita al cliente
# durante la conversación. Combina el horario laboral del agente con las citas
# ya agendadas (ver Jabvox::AgentAvailabilityService).
class Captain::Tools::CheckAvailabilityTool < Captain::Tools::BasePublicTool
  include Captain::Tools::Jabvox::AgendaHelpers

  description 'Consulta los horarios disponibles de un agente para agendar una ' \
              'cita. Devuelve una lista de huecos libres en los próximos días, ' \
              'según el horario laboral del agente y sus citas ya agendadas. ' \
              'Úsala antes de proponer horarios al cliente.'

  param :dias, type: 'integer', required: false,
               desc: 'Cuántos días hacia adelante consultar (por defecto 7, máximo 14).'
  param :agente_id, type: 'integer', required: false,
                    desc: 'ID del agente. Si se omite, se usa el agente asignado a la conversación.'

  def perform(tool_context, dias: 7, agente_id: nil)
    state = tool_context.state
    timezone = resolved_timezone(state)
    agent = resolve_agent(state, agente_id)
    return sin_agente_msg if agent.nil?

    days = dias.to_i.clamp(1, 14)
    service = availability_service(agent, timezone, days)
    return sin_horario_msg(agent) unless service.configured?

    slots = service.free_slots
    log_tool_usage('consultar_disponibilidad', { agente_id: agent.id, dias: days, slots: slots.size })
    return "El agente #{agent.name} no tiene huecos libres en los próximos #{days} días." if slots.empty?

    listado = slots.map { |s| "• #{format_slot(s, timezone)}" }.join("\n")
    "Horarios disponibles de #{agent.name} (zona #{timezone}):\n#{listado}"
  end

  private

  def availability_service(agent, timezone, days)
    tz = ActiveSupport::TimeZone[timezone] || ActiveSupport::TimeZone['UTC']
    today = tz.today
    Jabvox::AgentAvailabilityService.new(
      account: @assistant.account, user: agent,
      from: today, to: today + (days - 1).days, timezone: timezone
    )
  end

  def sin_agente_msg
    'No hay un agente asignado a esta conversación. Pregunta con qué agente se ' \
      'debe agendar (indica su ID) antes de consultar disponibilidad.'
  end

  def sin_horario_msg(agent)
    "El agente #{agent.name} aún no tiene horario laboral configurado en Jabvox IA. " \
      'Configúralo en Ajustes de agenda para poder ofrecer horarios disponibles.'
  end
end
