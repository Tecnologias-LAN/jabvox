# frozen_string_literal: true

# Base común de los nodos `jabvox.task.*`: resuelve tablero, etapa, responsables
# y fecha SIEMPRE dentro de la cuenta del run, y da la vista de salida.
class Jabvox::Flows::Nodes::Jabvox::TaskBase < Jabvox::Flows::Nodes::Jabvox::Base
  private

  def find_task!(raw, label = 'el ID de la tarea')
    task_id = require_id!(raw, label)
    task = account.jabvox_tasks.find_by(id: task_id)
    return task if task

    fail_with!("La tarea #{task_id} no existe en esta cuenta (puede haberse borrado). " \
               'Comprueba el ID de la tarea en el paso.')
  end

  def find_board!(raw, label = 'el tablero')
    board_id = require_id!(raw, label)
    board = account.jabvox_task_boards.find_by(id: board_id)
    return board if board

    fail_with!("El tablero #{board_id} no existe en esta cuenta. Elige un tablero de la lista: " \
               'con un tablero ajeno la tarea quedaría fuera de todos los tableros.')
  end

  # Etapa de la cuenta Y del tablero indicado: una etapa de otro tablero deja la
  # tarjeta invisible en el tablero al que se envía.
  def find_stage_in_board!(raw, board, label = 'la columna (etapa)')
    stage_id = require_id!(raw, label)
    stage = account.jabvox_task_stages.find_by(id: stage_id)
    fail_with!("La columna #{stage_id} no existe en esta cuenta. Elige una columna de la lista.") if stage.nil?
    return stage if stage.board_id == board.id

    fail_with!("La columna \"#{stage.name_jabvox}\" pertenece a otro tablero, no a " \
               "\"#{board.name_jabvox}\". Elige una columna de ese mismo tablero.")
  end

  # Valor de una lista cerrada. Vacío = respaldo; inválido = fallo explícito.
  def valid_enum(raw, allowed, label, fallback = nil)
    value = first_filled(raw)
    return fallback if value.blank?
    return value if allowed.include?(value)

    fail_with!("Valor no válido para #{label}: \"#{value}\". Valores admitidos: #{allowed.join(', ')}.")
  end

  # Responsables: `assigneeIds` (lista) más `assigneeId` (principal) al frente.
  # Se avisa de los que no están en la cuenta en vez de descartarlos en silencio.
  def assignee_ids
    return @assignee_ids if defined?(@assignee_ids)

    raw = (str_list(param(:assigneeId)) + str_list(param(:assigneeIds))).uniq
    @assignee_ids = raw.empty? ? [] : verified_user_ids(raw)
  end

  # ¿Se configuró algún responsable? Distingue "no tocar" de "lista vacía".
  def assignees_configured?
    !blank_param?(param(:assigneeId)) || str_list(param(:assigneeIds)).any?
  end

  def verified_user_ids(raw)
    wanted = raw.map(&:to_i)
    found = account.users.where(id: wanted).pluck(:id)
    missing = wanted - found
    fail_with!(missing_users_message(missing)) if missing.any?

    wanted
  end

  def missing_users_message(missing)
    "Estos responsables no son usuarios de esta cuenta: #{missing.join(', ')}. " \
      'Elige agentes de la lista; un usuario de otra cuenta no puede llevar la tarea.'
  end

  # Fecha de vencimiento. Si no se puede leer, se FALLA: guardar nil en silencio
  # dejaba la tarea sin vencimiento y sin aviso.
  def due_at
    raw = first_filled(param(:due_date), param(:dueDate))
    return nil if raw.blank?

    Time.zone.parse(raw) || fail_with!(bad_date_message(raw))
  rescue ArgumentError, TypeError
    fail_with!(bad_date_message(raw))
  end

  def bad_date_message(raw)
    "No se entiende la fecha de vencimiento \"#{raw}\". Usa 2026-08-15 o 2026-08-15 09:00."
  end

  def task_view(task)
    { 'id' => task.id, 'taskId' => task.id, 'title' => task.title_jabvox,
      'description' => task.description_jabvox, 'status' => task.status_jabvox,
      'priority' => task.priority_jabvox, 'position' => task.position_jabvox,
      'due_at' => task.due_at_jabvox&.iso8601,
      'board_id' => task.board_id, 'board_name' => task.board&.name_jabvox,
      'stage_id' => task.stage_id, 'stage_name' => task.stage&.name_jabvox,
      'lead_id' => task.jabvox_lead_id, 'assignee_id' => task.assignee_id,
      'assignee_ids' => task.assignees.pluck(:id),
      'assignee_names' => task.assignees.pluck(:name) }
  end
end
