# frozen_string_literal: true

# jabvox.task.create — crea una tarea en un tablero. El endpoint original NO
# comprobaba que el tablero fuera de la cuenta y dejaba tareas huérfanas.
class Jabvox::Flows::Nodes::Jabvox::TaskCreateNode < Jabvox::Flows::Nodes::Jabvox::TaskBase
  type 'jabvox.task.create'
  label 'Crear tarea'

  def perform
    title = require_title!
    board = find_board!(param(:boardId))
    stage = resolve_stage(board)
    task = account.jabvox_tasks.create!(create_attributes(board, stage, title))
    task.sync_assignees!(assignee_ids) if assignee_ids.any?
    task.log_activity(:created, nil, title: task.title_jabvox)
    task_view(task.reload)
  end

  private

  def create_attributes(board, stage, title)
    { board_id: board.id, stage_id: stage.id, title_jabvox: title,
      description_jabvox: first_filled(param(:description)).presence,
      priority_jabvox: valid_enum(param(:priority), JabvoxTask::PRIORITIES, 'la prioridad', 'normal'),
      status_jabvox: valid_enum(param(:status), JabvoxTask::STATUSES, 'el estado', 'open'),
      assignee_id: assignee_ids.first, due_at_jabvox: due_at,
      position_jabvox: int_or(param(:position), 0, min: 0),
      jabvox_lead_id: linked_lead&.id }
  end

  def require_title!
    text = first_filled(param(:title))
    fail_with!('Falta el título de la tarea: es obligatorio para crearla.') if text.blank?

    text
  end

  # Si no se elige etapa, entra en la primera columna del tablero.
  def resolve_stage(board)
    raw = first_filled(param(:stageId))
    return find_stage_in_board!(raw, board) if raw.present?

    stage = board.stages.ordered.first
    return stage if stage

    fail_with!("El tablero \"#{board.name_jabvox}\" no tiene ninguna columna: crea al menos una " \
               'columna en el tablero antes de crear tareas desde el flujo.')
  end

  def linked_lead
    raw = first_filled(param(:leadId))
    raw.present? ? find_lead!(raw) : nil
  end
end
