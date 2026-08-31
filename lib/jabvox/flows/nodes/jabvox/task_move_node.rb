# frozen_string_literal: true

# jabvox.task.move — mueve la tarjeta a otra columna del MISMO tablero y deja el
# cambio en el historial de la tarea.
class Jabvox::Flows::Nodes::Jabvox::TaskMoveNode < Jabvox::Flows::Nodes::Jabvox::TaskBase
  type 'jabvox.task.move'
  label 'Mover tarea'

  def perform
    task = find_task!(param(:taskId))
    from_stage = task.stage
    stage = find_stage_in_board!(param(:stageId), task.board, 'la columna destino')
    task.update!(stage_id: stage.id, position_jabvox: int_or(param(:position), 0, min: 0))
    log_move(task, from_stage, stage)
    task_view(task.reload).merge('moved' => from_stage.id != stage.id,
                                 'from_stage_id' => from_stage.id,
                                 'from_stage_name' => from_stage.name_jabvox)
  end

  private

  def log_move(task, from_stage, stage)
    return if from_stage.id == stage.id

    task.log_activity(:stage_changed, nil, from: from_stage.name_jabvox, to: stage.name_jabvox)
  end
end
