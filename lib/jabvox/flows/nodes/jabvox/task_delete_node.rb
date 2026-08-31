# frozen_string_literal: true

# jabvox.task.delete — borra la tarea. Devuelve datos útiles para encadenar: el
# borrado no tiene cuerpo y el registro mostraría "null".
class Jabvox::Flows::Nodes::Jabvox::TaskDeleteNode < Jabvox::Flows::Nodes::Jabvox::TaskBase
  type 'jabvox.task.delete'
  label 'Eliminar tarea'

  def perform
    task = find_task!(param(:taskId))
    view = task_view(task)
    task.destroy!
    { 'deleted' => true, 'taskId' => view['id'], 'title' => view['title'],
      'board_id' => view['board_id'], 'board_name' => view['board_name'],
      'stage_id' => view['stage_id'], 'stage_name' => view['stage_name'] }
  end
end
