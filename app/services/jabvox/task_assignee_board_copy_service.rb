# Copia una tarea al tablero personal de cada responsable que sea dueño de tablero.
#
# Se dispara al asignar responsables, si el tablero de ORIGEN tiene activada
# `copy_to_assignee_board_jabvox`. Para cada responsable se busca el destino configurado
# en ese tablero de origen (`JabvoxTaskAssigneeBoardTarget`): sin fila, no se copia nada
# para ese usuario — la automatización no adivina a cuál de sus tableros mandarlo.
#
# La copia es una tarea INDEPENDIENTE: no se sincronizan comentarios ni estado. Solo
# guarda `source_task_id` para saber de dónde salió y no duplicarla en cada reasignación.
class Jabvox::TaskAssigneeBoardCopyService
  def initialize(task)
    @task = task
  end

  # Devuelve las tareas creadas (vacío si no aplicaba nada).
  def perform
    return [] unless enabled?

    targets_by_owner.filter_map do |owner_id, target|
      copy_for(owner_id, target)
    end
  end

  private

  def enabled?
    # Una copia no vuelve a copiarse: sin esto, dos dueños con la copia activada en sus
    # tableros se reenviarían la tarea en cadena.
    @task.source_task_id.nil? && @task.board&.copy_to_assignee_board_jabvox?
  end

  # A quién se le copia: los responsables de la tarea y, además, el dueño del tablero de
  # origen —que debe enterarse de lo que se abre en su tablero aunque no sea responsable—.
  #
  # El destino se DEDUCE: si el usuario es dueño de un tablero, ese es el suyo y no hay
  # nada que configurar. La tabla de destinos solo hace falta para desempatar cuando es
  # dueño de varios; sin fila, se usa el primero por posición. Antes era obligatoria y, al
  # faltar, la copia no ocurría sin decir por qué.
  #
  # Se excluye el tablero de origen: quien ya tiene la tarea delante no necesita una copia
  # en la misma pantalla.
  def targets_by_owner
    candidate_ids = (@task.task_assignees.pluck(:user_id) + [@task.board.owner_id]).compact.uniq
    return {} if candidate_ids.empty?

    configured = @task.board.assignee_board_targets
                      .where(owner_id: candidate_ids)
                      .includes(:target_board)
                      .index_by(&:owner_id)

    candidate_ids.each_with_object({}) do |owner_id, result|
      board = configured[owner_id]&.target_board || default_board_for(owner_id)
      next if board.nil? || board.id == @task.board_id

      result[owner_id] = board
    end
  end

  # Tablero propio del usuario cuando no hay destino configurado. Con varios, el primero
  # por posición: elegir otro es lo que resuelve la tabla de destinos.
  def default_board_for(owner_id)
    JabvoxTaskBoard
      .where(account_id: @task.account_id, owner_id: owner_id)
      .order(:position_jabvox, :id)
      .first
  end

  def copy_for(owner_id, board)
    # El destino pudo cambiar de cuenta después de configurarse.
    return if board.nil? || board.account_id != @task.account_id
    return if board.id == @task.board_id
    return if already_copied?(board)

    stage = initial_stage(board)
    return if stage.nil?

    create_copy(board, stage, owner_id)
  end

  # Reasignar la misma tarea no debe generar una copia nueva cada vez.
  def already_copied?(board)
    JabvoxTask.exists?(source_task_id: @task.id, board_id: board.id)
  end

  def initial_stage(board)
    board.initial_stage
  end

  def create_copy(board, stage, owner_id)
    copy = JabvoxTask.create!(
      account_id: @task.account_id,
      board_id: board.id,
      stage_id: stage.id,
      assignee_id: owner_id,
      contact_id: @task.contact_id,
      created_by_id: @task.created_by_id,
      source_task_id: @task.id,
      title_jabvox: @task.title_jabvox,
      description_jabvox: @task.description_jabvox,
      priority_jabvox: @task.priority_jabvox,
      status_jabvox: 'open',
      due_at_jabvox: @task.due_at_jabvox
    )
    # El dueño es el responsable de su propia copia.
    copy.task_assignees.create!(user_id: owner_id, account_id: @task.account_id)
    copy
  end
end
