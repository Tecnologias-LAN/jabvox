# frozen_string_literal: true

# Forma pública de una tarea para el frontend de Tareas.
#
# Las claves de salida se conservan tal cual (incluida `jabvox_lead_id`, que hoy lleva el
# contacto): el tablero, el calendario y los enlaces guardados las usan, y renombrarlas
# rompería pantallas que no se están tocando.
class Jabvox::TaskSerializer
  def initialize(task, lead_label:)
    @task = task
    @lead_label = lead_label
  end

  def call
    base.merge(location).merge(recurrence).merge(automations)
  end

  private

  def location
    { board_name: @task.board.name_jabvox, stage_name: @task.stage.name_jabvox }
  end

  def base
    {
      id: @task.id, board_id: @task.board_id, stage_id: @task.stage_id,
      jabvox_lead_id: @task.contact_id,
      lead_name: @task.contact && @lead_label.call(@task.contact),
      assignee_id: @task.assignee_id, assignee_name: @task.assignee&.name,
      assignees: @task.assignees.map { |u| { id: u.id, name: u.name, thumbnail: u.avatar_url } },
      title_jabvox: @task.title_jabvox, description_jabvox: @task.description_jabvox,
      priority_jabvox: @task.priority_jabvox, status_jabvox: @task.status_jabvox,
      due_at_jabvox: @task.due_at_jabvox, due_dates_jabvox: @task.due_dates_jabvox,
      position_jabvox: @task.position_jabvox, created_at: @task.created_at
    }
  end

  def recurrence
    {
      recurrence_unit_jabvox: @task.recurrence_unit_jabvox,
      recurrence_count_jabvox: @task.recurrence_count_jabvox,
      recurrence_until_jabvox: @task.recurrence_until_jabvox,
      recurrence_parent_id: @task.recurrence_parent_id
    }
  end

  def automations
    {
      automations_count: @task.automations.size,
      active_automations_count: @task.automations.count(&:active_jabvox)
    }
  end
end
