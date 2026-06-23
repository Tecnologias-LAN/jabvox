class Api::V1::Accounts::Jabvox::Tasks::TasksController < Api::V1::Accounts::Jabvox::Tasks::BaseController
  before_action :set_task, only: %i[show update destroy move]

  # Filterable by board, lead, and date range (board view + calendar view + per-lead filter).
  def index
    tasks = scoped.includes(:stage, :jabvox_lead, :assignee)
    tasks = tasks.where(board_id: params[:board_id]) if params[:board_id].present?
    tasks = tasks.where(jabvox_lead_id: params[:lead_id]) if params[:lead_id].present?
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
      render json: serialize(task), status: :created
    else
      render json: { errors: task.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @task.update(task_params)
      render json: serialize(@task)
    else
      render json: { errors: @task.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @task.destroy!
    head :no_content
  end

  # Move a card to another stage (and optional position). Changing stage_id fires the
  # destination stage's automations via the model's after_commit hook.
  def move
    stage = Current.account.jabvox_task_stages.find(params.require(:stage_id))
    @task.update!(stage_id: stage.id, position_jabvox: params[:position].to_i)
    render json: serialize(@task.reload)
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

  def task_params
    params.require(:task).permit(
      :board_id, :stage_id, :jabvox_lead_id, :assignee_id, :title_jabvox,
      :description_jabvox, :priority_jabvox, :status_jabvox, :due_at_jabvox, :position_jabvox,
      due_dates_jabvox: []
    )
  end

  def serialize(task)
    {
      id: task.id, board_id: task.board_id, stage_id: task.stage_id,
      jabvox_lead_id: task.jabvox_lead_id,
      lead_name: task.jabvox_lead&.contact&.name || (task.jabvox_lead && "Lead ##{task.jabvox_lead.lead_number}"),
      assignee_id: task.assignee_id, assignee_name: task.assignee&.name,
      title_jabvox: task.title_jabvox, description_jabvox: task.description_jabvox,
      priority_jabvox: task.priority_jabvox, status_jabvox: task.status_jabvox,
      due_at_jabvox: task.due_at_jabvox, due_dates_jabvox: task.due_dates_jabvox,
      position_jabvox: task.position_jabvox, created_at: task.created_at
    }
  end
end
