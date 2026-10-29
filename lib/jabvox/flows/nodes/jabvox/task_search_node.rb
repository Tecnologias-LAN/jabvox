# frozen_string_literal: true

# jabvox.task.search — LECTURA de tareas. Dos operaciones: `list` (obtener tareas
# con filtros combinables) y `by_id` (una tarea concreta). Ambas normalizan la
# salida a `{ operation, count, tasks: [...] }`, de modo que un bucle sobre
# `{{node.<id>.items}}` funciona igual venga de donde venga.
class Jabvox::Flows::Nodes::Jabvox::TaskSearchNode < Jabvox::Flows::Nodes::Jabvox::TaskBase
  type 'jabvox.task.search'
  label 'Obtener Tareas'
  items_path 'tasks'

  # Tope de seguridad por página: una cuenta con miles de tareas no puede tumbar
  # el nodo. `limit` es OPCIONAL y se acota a este máximo, nunca "sin límite".
  SAFETY_LIMIT = 500
  DEFAULT_LIMIT = 50

  def perform
    case first_filled(param(:operation), 'list')
    when 'by_id' then by_id
    else by_list
    end
  end

  private

  # Una tarea concreta por su ID interno. Se acota a la cuenta en `find_task!`.
  def by_id
    task = find_task!(param(:taskId))
    { 'operation' => 'by_id', 'count' => 1, 'task' => task_view(task),
      'tasks' => [task_view(task)] }
  end

  # Lista filtrada y paginada. Los filtros son combinables: cada uno se aplica
  # solo si viene con valor, para que "sin filtro" signifique "no acotar".
  def by_list
    scope = filtered_scope
    total = scope.count
    rows = scope.order(created_at: :desc).limit(limit).offset(offset).to_a

    { 'operation' => 'list', 'count' => rows.length, 'total' => total,
      'page' => page, 'per_page' => limit, 'hasMore' => (offset + rows.length) < total,
      'tasks' => rows.map { |task| task_view(task) } }
  end

  # Base: tareas de la cuenta, precargando lo que `task_view` necesita para no
  # disparar una consulta por tarea (contacto, empresa, tablero, etapa, responsables).
  def base_scope
    account.jabvox_tasks
           .includes(:board, :stage, :assignee, :assignees, contact: :company)
  end

  def filtered_scope
    scope = apply_attribute_filters(base_scope)
    scope = apply_date_range(scope, :due_at_jabvox, param(:dueFrom), param(:dueTo))
    apply_date_range(scope, :created_at, param(:createdFrom), param(:createdTo))
  end

  # Cada filtro se aplica solo si viene con valor: "sin filtro" = "no acotar".
  def apply_attribute_filters(scope)
    scope = scope.where(board_id: board.id) if board
    scope = scope.where(stage_id: stage.id) if stage
    scope = scope.where(assignee_id: param(:assigneeId)) if param(:assigneeId).present?
    scope = scope.where(status_jabvox: status) if status
    scope = scope.where(priority_jabvox: priority) if priority
    scope = scope.where(contact_id: contact_id) if contact_id
    scope
  end

  # Tablero y etapa validados contra la cuenta (y la etapa, contra el tablero):
  # un id de otra cuenta se trata como "no existe", igual que el resto de nodos.
  def board
    return @board if defined?(@board)

    @board = blank_param?(param(:boardId)) ? nil : find_board!(param(:boardId))
  end

  def stage
    return @stage if defined?(@stage)

    raw = first_filled(param(:stageId))
    @stage = if raw.blank?
               nil
             elsif board
               find_stage_in_board!(raw, board)
             else
               find_stage_anywhere!(raw)
             end
  end

  # Etapa sin tablero elegido: debe seguir siendo de la cuenta.
  def find_stage_anywhere!(raw)
    stage = account.jabvox_task_stages.find_by(id: require_id!(raw, 'la columna'))
    return stage if stage

    fail_with!("La columna #{raw} no existe en esta cuenta. Elige una columna de la lista.")
  end

  def status
    valid_enum(param(:status), JabvoxTask::STATUSES, 'el estado')
  end

  def priority
    valid_enum(param(:priority), JabvoxTask::PRIORITIES, 'la prioridad')
  end

  # El contacto vinculado se referencia por su ID INTERNO; se valida que sea de la
  # cuenta para no filtrar por un contacto ajeno.
  def contact_id
    return @contact_id if defined?(@contact_id)

    @contact_id = blank_param?(param(:contactId)) ? nil : find_contact!(param(:contactId)).id
  end

  # Rango [desde, hasta] sobre una columna de fecha. Cada extremo es opcional.
  def apply_date_range(scope, column, from_raw, to_raw)
    from = parse_time(from_raw)
    to = parse_time(to_raw)
    scope = scope.where("#{column} >= ?", from) if from
    scope = scope.where("#{column} <= ?", to) if to
    scope
  end

  def parse_time(raw)
    return nil if blank_param?(raw)

    Time.zone.parse(raw.to_s) || fail_with!(bad_range_message(raw))
  rescue ArgumentError, TypeError
    fail_with!(bad_range_message(raw))
  end

  def bad_range_message(raw)
    "No se entiende la fecha \"#{raw}\" del filtro. Usa 2026-08-15 o 2026-08-15 09:00."
  end

  def limit
    @limit ||= int_or(param(:limit), DEFAULT_LIMIT, min: 1, max: SAFETY_LIMIT)
  end

  def page
    @page ||= int_or(param(:page), 1, min: 1)
  end

  def offset
    (page - 1) * limit
  end
end
