class Api::V1::Accounts::Jabvox::Tasks::TasksController < Api::V1::Accounts::Jabvox::Tasks::BaseController
  before_action :set_task, only: %i[show update destroy move activities automation_runs comment]
  # Creating/editing/moving/deleting tasks is a management action (custom-role gated;
  # standard agents keep historical behavior, admins always pass).
  before_action -> { jabvox_gate!('jabvox_tasks_manage') }, only: %i[create update destroy move]
  # Borrar solo el administrador: un tablero o una columna arrastran en cascada
  # todas sus tareas, y eso no se delega en ningún rol.
  before_action :ensure_admin_for_destroy!, only: %i[destroy]

  # Filterable by board, lead, and date range (board view + calendar view + per-lead filter).
  def index
    tasks = scoped.includes(:stage, :contact, :assignee, :assignees, :automations)
    tasks = tasks.where(board_id: params[:board_id]) if params[:board_id].present?
    # Se filtra por contacto; `lead_id` se sigue aceptando por compatibilidad con enlaces
    # y llamadas antiguas, resolviéndolo al contacto correspondiente.
    tasks = tasks.where(contact_id: params[:contact_id]) if params[:contact_id].present?
    # `lead_id` es hoy el id del contacto: se acepta como alias para los enlaces guardados.
    tasks = tasks.where(contact_id: params[:lead_id]) if params[:lead_id].present?
    tasks = filter_by_date(tasks)
    render json: tasks.ordered.map { |t| serialize(t) }
  end

  def show
    render json: serialize(@task)
  end

  def create
    task = scoped.new(task_params)
    task.account = Current.account
    task.created_by = current_user
    if task.save
      apply_assignees(task)
      task.log_activity(:created, current_user, title: task.title_jabvox)
      render json: serialize(task.reload), status: :created
    else
      render json: { errors: task.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    before = task_snapshot(@task)
    if @task.update(task_params)
      apply_assignees(@task) if assignee_ids_param
      # Se recargan etapa y contacto para que sus nombres reflejen los ids nuevos al
      # registrar el cambio.
      @task.association(:stage).reload
      @task.association(:contact).reload
      log_field_changes(@task, before)
      render json: serialize(@task.reload)
    else
      render json: { errors: @task.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @task.destroy!
    head :no_content
  end

  # Move a card to another stage at an optional position, recompacting the destination
  # column so cards never share a position. Changing stage_id fires the destination stage's
  # automations via the model's after_commit hook. Reordering within the same column (same
  # stage, new position) just resequences without firing stage automations.
  def move
    stage = Current.account.jabvox_task_stages.find(params.require(:stage_id))
    from_stage = @task.stage
    @task.reorder_within_stage!(stage, params[:position])
    if from_stage.id != stage.id
      @task.log_activity(:stage_changed, current_user,
                         from: from_stage.name_jabvox, to: stage.name_jabvox)
    end
    render json: serialize(@task.reload)
  end

  # Append-only history for a single task, newest first.
  #
  # Con tope: el historial crece sin fin (cada cambio de campo y cada comentario suman una
  # fila), y una tarea muy trabajada devolvía cientos de entradas de golpe. Se sirve igual
  # que `automation_runs`, que ya limitaba a 50.
  MAX_ACTIVITIES = 200

  def activities
    logs = @task.activities.includes(:user).reorder(created_at: :desc).limit(MAX_ACTIVITIES)
    render json: logs.map { |a| serialize_activity(a) }
  end

  # Comentario de resolución: lo escribe quien está atendiendo la tarea y queda en el mismo
  # historial que los cambios de campos, para leer el caso de corrido.
  #
  # No pasa por `jabvox_tasks_manage` a propósito: comentar es parte de resolver, no de
  # administrar el tablero. Un agente que trabaja la tarea puede comentarla aunque no
  # pueda crear ni borrar tareas.
  def comment
    body = params[:body].to_s.strip
    return render json: { error: 'El comentario no puede estar vacío' }, status: :unprocessable_entity if body.blank?

    activity = @task.log_activity(
      JabvoxTaskActivity::COMMENT, current_user,
      body: body.first(JabvoxTaskActivity::MAX_COMMENT_LENGTH)
    )
    render json: serialize_activity(activity), status: :created
  end

  # Automation dispatch log for a single task (what was sent and when), newest first.
  def automation_runs
    runs = @task.automation_runs.limit(50)
    render json: runs.map { |r| serialize_run(r) }
  end

  private

  def scoped
    Current.account.jabvox_tasks
  end

  def set_task
    @task = scoped.find(params[:id])
  end

  def filter_by_date(tasks)
    tasks = tasks.where(due_at_jabvox: params[:from]..) if params[:from].present?
    tasks = tasks.where(due_at_jabvox: ..params[:to]) if params[:to].present?
    tasks
  end

  # NOTE: assignee_ids is intentionally NOT permitted here. It's a has_many-through
  # association writer, so letting it through task_params would make AR build join rows
  # without account_id (which is NOT NULL) and raise RecordInvalid. Assignees are synced
  # separately in #apply_assignees, which sets account_id explicitly.
  def task_params
    permitted = params.require(:task).permit(
      :board_id, :stage_id, :contact_id, :jabvox_lead_id, :assignee_id, :title_jabvox,
      :description_jabvox, :priority_jabvox, :status_jabvox, :due_at_jabvox, :position_jabvox,
      :recurrence_unit_jabvox, :recurrence_count_jabvox, :recurrence_until_jabvox,
      due_dates_jabvox: []
    )
    # `jabvox_lead_id` se sigue aceptando como alias de `contact_id`: el frontend guardado y
    # las integraciones existentes lo envían, y tras retirar Leads ambos son el contacto.
    legacy = permitted.delete(:jabvox_lead_id)
    permitted[:contact_id] = legacy if legacy.present? && permitted[:contact_id].blank?
    permitted
  end

  # Raw assignee_ids from the request (nil if the key was not sent, so update leaves them alone).
  def assignee_ids_param
    return @assignee_ids_param if defined?(@assignee_ids_param)

    raw = params.dig(:task, :assignee_ids)
    @assignee_ids_param = raw.nil? ? nil : Array(raw)
  end

  # Sync assignees from assignee_ids (falling back to the legacy single assignee_id) and
  # log each add/remove. Looks up names once for readable activity metadata.
  def apply_assignees(task)
    ids = assignee_ids_param
    ids = [task.assignee_id].compact if ids.nil?
    added, removed = task.sync_assignees!(ids)
    return if added.empty? && removed.empty?

    names = User.where(id: added + removed).pluck(:id, :name).to_h
    added.each  { |uid| task.log_activity(:assignee_added, current_user, user_id: uid, user_name: names[uid]) }
    removed.each { |uid| task.log_activity(:assignee_removed, current_user, user_id: uid, user_name: names[uid]) }
  end

  # Snapshot of the fields we track in the activity log. Lead and stage are stored with both
  # their id and a human-readable name so the history can say what changed.
  def task_snapshot(task)
    {
      title: task.title_jabvox, description: task.description_jabvox,
      status: task.status_jabvox, priority: task.priority_jabvox,
      due_at: task.due_at_jabvox,
      lead_id: task.contact_id, lead_name: lead_label(task.contact),
      stage_id: task.stage_id, stage_name: task.stage&.name_jabvox
    }
  end

  def log_field_changes(task, before)
    log_title_change(task, before)
    log_description_change(task, before)
    log_status_change(task, before)
    log_priority_change(task, before)
    log_due_date_change(task, before)
    log_stage_change(task, before)
    log_lead_change(task, before)
  end

  def log_title_change(task, before)
    return if before[:title] == task.title_jabvox

    task.log_activity(:title_changed, current_user, from: before[:title], to: task.title_jabvox)
  end

  def log_description_change(task, before)
    return if before[:description].to_s == task.description_jabvox.to_s

    task.log_activity(:description_changed, current_user)
  end

  def log_status_change(task, before)
    return if before[:status] == task.status_jabvox

    task.log_activity(:status_changed, current_user, from: before[:status], to: task.status_jabvox)
  end

  def log_priority_change(task, before)
    return if before[:priority] == task.priority_jabvox

    task.log_activity(:priority_changed, current_user, from: before[:priority], to: task.priority_jabvox)
  end

  def log_due_date_change(task, before)
    return if before[:due_at] == task.due_at_jabvox

    task.log_activity(:due_date_changed, current_user,
                      from: before[:due_at]&.iso8601, to: task.due_at_jabvox&.iso8601)
  end

  def log_stage_change(task, before)
    return if before[:stage_id] == task.stage_id

    task.log_activity(:stage_changed, current_user,
                      from: before[:stage_name], to: task.stage&.name_jabvox)
  end

  def log_lead_change(task, before)
    return if before[:lead_id] == task.contact_id

    task.log_activity(:lead_changed, current_user,
                      from: before[:lead_name], to: lead_label(task.contact))
  end

  # Nombre legible del contacto de la tarea (o raya cuando no tiene).
  def lead_label(contact)
    return '—' if contact.nil?

    contact.name.presence || "Contacto ##{contact.id}"
  end

  def serialize(task)
    Jabvox::TaskSerializer.new(task, lead_label: method(:lead_label)).call
  end

  def serialize_run(run)
    {
      id: run.id, automation_id: run.automation_id, channel_jabvox: run.channel_jabvox,
      status_jabvox: run.status_jabvox, recipients_count_jabvox: run.recipients_count_jabvox,
      detail_jabvox: run.detail_jabvox, run_at_jabvox: run.run_at_jabvox
    }
  end

  def serialize_activity(activity)
    {
      id: activity.id,
      action: activity.action_jabvox,
      metadata: activity.metadata_jabvox,
      user_id: activity.user_id,
      user_name: activity.user&.name,
      created_at: activity.created_at
    }
  end
end
