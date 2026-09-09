# frozen_string_literal: true

# Tool nativa de Jabvox IA: crea una tarea en un tablero/etapa de Jabvox,
# vinculada al lead del contacto de la conversación y asignada a un agente.
# Sigue el patrón de creación de Hermes/flows (modelo directo + sync_assignees!).
class Captain::Tools::CreateTaskTool < Captain::Tools::BasePublicTool
  include Captain::Tools::Jabvox::AgendaHelpers

  PRIORITIES = %w[low normal high urgent].freeze

  description 'Crea una tarea en un tablero de tareas de Jabvox, vinculada al ' \
              'cliente de esta conversación. Antes de crearla, usa la herramienta ' \
              'de listar tableros para conocer el tablero_id y la etapa_id. Si no ' \
              'indicas etapa, se usa la primera etapa del tablero.'

  param :titulo, type: 'string', desc: 'Título de la tarea (obligatorio).'
  param :tablero_id, type: 'integer', desc: 'ID del tablero donde crear la tarea.'
  param :etapa_id, type: 'integer', required: false,
                   desc: 'ID de la etapa. Si se omite, la primera etapa del tablero.'
  param :descripcion, type: 'string', required: false, desc: 'Descripción o detalle de la tarea.'
  param :prioridad, type: 'string', required: false,
                    desc: 'Prioridad: low, normal, high o urgent (por defecto normal).'
  param :vence_el, type: 'string', required: false,
                   desc: 'Fecha límite en ISO 8601, p. ej. "2026-09-20T18:00".'
  param :agente_id, type: 'integer', required: false,
                    desc: 'ID del agente responsable. Si se omite, el asignado a la conversación.'

  def perform(tool_context, titulo:, tablero_id:, etapa_id: nil, descripcion: nil,
              prioridad: nil, vence_el: nil, agente_id: nil)
    return 'El título de la tarea es obligatorio.' if titulo.blank?

    board = @assistant.account.jabvox_task_boards.find_by(id: tablero_id)
    return "No existe el tablero con id #{tablero_id}. Usa la herramienta de listar tableros." if board.nil?

    stage = resolve_stage(board, etapa_id)
    return "El tablero \"#{board.name_jabvox}\" no tiene etapas configuradas." if stage.nil?

    state = tool_context.state
    agent = resolve_agent(state, agente_id)
    task = persist_task(board, stage, agent, state,
                        titulo: titulo, descripcion: descripcion,
                        prioridad: prioridad, vence_el: vence_el)

    log_tool_usage('crear_tarea', { task_id: task.id, board_id: board.id, stage_id: stage.id })
    "Tarea \"#{task.title_jabvox}\" creada en el tablero \"#{board.name_jabvox}\" " \
      "(etapa \"#{stage.name_jabvox}\")#{agent ? ", asignada a #{agent.name}" : ''}."
  rescue ActiveRecord::RecordInvalid => e
    "No se pudo crear la tarea: #{e.record.errors.full_messages.to_sentence}"
  end

  private

  # Crea la tarea (modelo directo, patrón Hermes/flows) y sincroniza responsable
  # e historial. Devuelve la tarea persistida.
  def persist_task(board, stage, agent, state, titulo:, descripcion:, prioridad:, vence_el:)
    task = @assistant.account.jabvox_tasks.new(
      board_id: board.id,
      stage_id: stage.id,
      title_jabvox: titulo,
      description_jabvox: descripcion,
      priority_jabvox: normalizar_prioridad(prioridad),
      status_jabvox: 'open',
      due_at_jabvox: parse_time(vence_el, resolved_timezone(state)),
      jabvox_lead_id: conversation_lead(state)&.id,
      assignee_id: agent&.id
    )
    task.created_by = agent
    task.save!
    task.sync_assignees!([agent.id]) if agent
    task.log_activity(:created, agent, title: task.title_jabvox)
    task
  end

  def resolve_stage(board, etapa_id)
    if etapa_id.present?
      board.stages.find_by(id: etapa_id)
    else
      board.stages.ordered.first
    end
  end

  def normalizar_prioridad(value)
    p = value.to_s.downcase
    PRIORITIES.include?(p) ? p : 'normal'
  end
end
