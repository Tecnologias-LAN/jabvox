# frozen_string_literal: true

# Crea la siguiente ocurrencia de una tarea que se repite.
#
# El disparo es "al completar", no por calendario: la siguiente semana solo aparece cuando
# se cierra la de esta. Así una tarea que nadie atendió no genera doce copias muertas; a
# cambio, quedarse sin completar se ve como una tarea vencida en la etapa inactiva, que es
# justo la señal que interesa.
#
# La copia hereda lo que define el trabajo (título, descripción, prioridad, responsables,
# contacto, recurrencia) y nace limpia de lo que pertenece a la ocurrencia cerrada
# (comentarios, historial, fecha de aviso).
class Jabvox::TaskRecurrenceService
  # Minuto y hora permiten recurrencias intradía ("recordar cada 2 horas"), que antes
  # obligaban a crear una tarea por cada repetición.
  UNITS = %w[minute hour day week month year].freeze

  def initialize(task)
    @task = task
  end

  # Devuelve la tarea nueva, o nil si no había que crear ninguna.
  def create_next
    return unless repeatable?

    next_due = next_due_at
    return if next_due.nil?
    return if ended?(next_due)

    build_next(next_due).tap do |copy|
      copy.save!
      copy.assignee_ids = @task.assignee_ids if @task.respond_to?(:assignee_ids)
      copy.log_activity(:recurrence_created, nil, from_task_id: @task.id,
                                                  due_at: next_due.iso8601)
    end
  end

  private

  def repeatable?
    UNITS.include?(@task.recurrence_unit_jabvox.to_s) && @task.recurrence_count_jabvox.to_i.positive?
  end

  # Se cuenta desde la fecha de vencimiento, no desde hoy: una tarea semanal que se cierra
  # con tres días de retraso sigue venciendo el mismo día de la semana siguiente.
  def next_due_at
    base = @task.due_at_jabvox || Time.current
    base + interval
  end

  def interval
    count = @task.recurrence_count_jabvox.to_i
    case @task.recurrence_unit_jabvox
    when 'minute' then count.minutes
    when 'hour' then count.hours
    when 'day' then count.days
    when 'week' then count.weeks
    when 'month' then count.months
    when 'year' then count.years
    end
  end

  def ended?(next_due)
    @task.recurrence_until_jabvox.present? && next_due > @task.recurrence_until_jabvox
  end

  # Nace en la etapa inicial del tablero; si nadie marcó cuál es, en la primera.
  def initial_stage
    board = @task.board
    board.initial_stage
  end

  def build_next(next_due)
    JabvoxTask.new(
      account_id: @task.account_id,
      board_id: @task.board_id,
      stage_id: initial_stage&.id || @task.stage_id,
      assignee_id: @task.assignee_id,
      contact_id: @task.contact_id,
      created_by_id: @task.created_by_id,
      title_jabvox: @task.title_jabvox,
      description_jabvox: @task.description_jabvox,
      priority_jabvox: @task.priority_jabvox,
      status_jabvox: 'open',
      due_at_jabvox: next_due,
      recurrence_unit_jabvox: @task.recurrence_unit_jabvox,
      recurrence_count_jabvox: @task.recurrence_count_jabvox,
      recurrence_until_jabvox: @task.recurrence_until_jabvox,
      recurrence_parent_id: @task.recurrence_parent_id || @task.id
    )
  end
end
