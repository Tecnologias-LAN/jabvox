# frozen_string_literal: true

# Pasada diaria sobre las tareas con fecha: avisa de lo que vence y aparta lo que ya venció.
#
# Dos cosas, en este orden:
#
#   1. RECORDATORIO de lo que vence hoy o mañana, una sola vez por ocurrencia
#      (`reminder_sent_at_jabvox` evita repetirlo en cada pasada).
#   2. Lo VENCIDO sin completar se mueve a la etapa marcada como inactiva. Así una tarea
#      recurrente que nadie atendió queda a la vista en vez de envejecer en la columna de
#      trabajo; su siguiente ocurrencia solo nace al completarla, por diseño.
#
# Solo se tocan tareas abiertas: una completada ya cumplió.
class Jabvox::TaskDueSweeperService
  REMINDER_WINDOW = 1.day

  def call
    Account.find_each do |account|
      next unless account.feature_enabled?('jabvox_tasks')

      remind(account)
      deactivate_overdue(account)
    end
  end

  private

  def remind(account)
    due_soon(account).find_each do |task|
      Jabvox::TaskReminderService.new(task).call
    rescue StandardError => e
      Rails.logger.error "[TaskDueSweeper] aviso fallido tarea #{task.id}: #{e.message}"
    end
  end

  # Vence dentro de la ventana y no se ha avisado desde la última vez que cambió la fecha.
  def due_soon(account)
    account.jabvox_tasks
           .where(status_jabvox: 'open')
           .where(due_at_jabvox: Time.current..(Time.current + REMINDER_WINDOW))
           .where(reminder_sent_at_jabvox: nil)
  end

  # Cada tablero decide cuál es su etapa inactiva; el que no la tenga marcada se salta.
  def deactivate_overdue(account)
    inactive_by_board = account.jabvox_task_stages.where(role_jabvox: 'inactive').index_by(&:board_id)
    return if inactive_by_board.empty?

    overdue(account).where(board_id: inactive_by_board.keys).find_each do |task|
      stage = inactive_by_board[task.board_id]
      next if stage.nil? || task.stage_id == stage.id

      move_to_inactive(task, stage)
    rescue StandardError => e
      Rails.logger.error "[TaskDueSweeper] no se pudo apartar la tarea #{task.id}: #{e.message}"
    end
  end

  def overdue(account)
    account.jabvox_tasks.where(status_jabvox: 'open').where(due_at_jabvox: ...Time.current)
  end

  def move_to_inactive(task, stage)
    from = task.stage
    task.update!(stage_id: stage.id)
    task.log_activity(:stage_changed, nil, from: from&.name_jabvox, to: stage.name_jabvox,
                                           reason: 'vencida')
  end
end
