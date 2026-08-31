# frozen_string_literal: true

# jabvox.task.update — actualiza SOLO lo configurado. Un campo en blanco no se
# toca: enviarlo vacío borraría el dato que la tarea ya tenía.
class Jabvox::Flows::Nodes::Jabvox::TaskUpdateNode < Jabvox::Flows::Nodes::Jabvox::TaskBase
  type 'jabvox.task.update'
  label 'Actualizar tarea'

  def perform
    task = find_task!(param(:taskId))
    attrs = writable_attributes(task)
    fail_with!(nothing_to_update_message) if attrs.blank? && !assignees_configured?

    task.update!(attrs) if attrs.present?
    task.sync_assignees!(assignee_ids) if assignees_configured?
    task_view(task.reload).merge('updated' => true)
  end

  private

  def writable_attributes(task)
    { title_jabvox: text_param(:title), description_jabvox: text_param(:description),
      priority_jabvox: valid_enum(param(:priority), JabvoxTask::PRIORITIES, 'la prioridad'),
      status_jabvox: valid_enum(param(:status), JabvoxTask::STATUSES, 'el estado'),
      due_at_jabvox: due_at, jabvox_lead_id: new_lead_id, stage_id: new_stage_id(task) }.compact
  end

  def text_param(key)
    blank_param?(param(key)) ? nil : first_filled(param(key))
  end

  def new_lead_id
    blank_param?(param(:leadId)) ? nil : find_lead!(param(:leadId)).id
  end

  def new_stage_id(task)
    blank_param?(param(:stageId)) ? nil : target_stage(task).id
  end

  # La etapa se valida contra el tablero de la tarea, no contra `boardId` (que en
  # el catálogo solo filtra el selector).
  def target_stage(task)
    find_stage_in_board!(param(:stageId), task.board, 'la columna destino')
  end

  def nothing_to_update_message
    'No se configuró ningún campo que actualizar en la tarea: rellena al menos uno ' \
      '(título, descripción, prioridad, estado, vencimiento, responsables, columna o lead).'
  end
end
