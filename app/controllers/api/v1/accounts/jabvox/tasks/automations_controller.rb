# CRUD for a task's recurring automations (send email/sms/message every N days/weeks/months),
# plus run_now to dispatch one immediately for testing, and a runs feed for the audit trail.
class Api::V1::Accounts::Jabvox::Tasks::AutomationsController < Api::V1::Accounts::Jabvox::Tasks::BaseController
  before_action :set_task
  before_action :set_automation, only: %i[update destroy run_now]
  # Managing task automations is custom-role gated; standard agents keep historical behavior,
  # admins always pass.
  before_action -> { jabvox_gate!('jabvox_tasks_manage') }, only: %i[create update destroy run_now]
  # Borrar solo el administrador: un tablero o una columna arrastran en cascada
  # todas sus tareas, y eso no se delega en ningún rol.
  before_action :ensure_admin_for_destroy!, only: %i[destroy]

  def index
    render json: @task.automations.order(created_at: :desc).map { |a| serialize(a) }
  end

  def create
    automation = @task.automations.new(automation_params)
    automation.account = Current.account
    automation.created_by = current_user
    if automation.save
      render json: serialize(automation), status: :created
    else
      render json: { errors: automation.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @automation.update(automation_params)
      render json: serialize(@automation)
    else
      render json: { errors: @automation.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @automation.destroy!
    head :no_content
  end

  # Dispatch this automation right now (does not alter the recurrence schedule beyond the
  # normal mark_ran! bump). Returns the resulting run.
  def run_now
    run = Jabvox::TaskAutomationDispatchService.new(@automation).perform
    render json: serialize_run(run)
  end

  private

  def set_task
    @task = Current.account.jabvox_tasks.find(params[:task_id])
  end

  def set_automation
    @automation = @task.automations.find(params[:id])
  end

  def automation_params
    params.require(:automation).permit(
      :name_jabvox, :channel_jabvox, :recipients_jabvox, :manual_email_jabvox,
      :manual_phone_jabvox, :interval_unit_jabvox, :interval_count_jabvox,
      :email_template_id, :inbox_id, :sms_provider_id, :subject_jabvox, :body_jabvox,
      :active_jabvox, :start_at_jabvox, :end_at_jabvox,
      :max_runs_jabvox, :schedule_mode_jabvox,
      :template_name_jabvox, :template_language_jabvox,
      # El mapeo de variables es un hash de forma libre ({"1" => {source:, field:}}), así
      # que se permite entero y el servicio que lo lee valida campo por campo.
      template_params_jabvox: {}
    )
  end

  def serialize(automation)
    {
      id: automation.id, task_id: automation.task_id,
      name_jabvox: automation.name_jabvox, channel_jabvox: automation.channel_jabvox,
      recipients_jabvox: automation.recipients_jabvox,
      manual_email_jabvox: automation.manual_email_jabvox,
      manual_phone_jabvox: automation.manual_phone_jabvox,
      interval_unit_jabvox: automation.interval_unit_jabvox,
      interval_count_jabvox: automation.interval_count_jabvox,
      email_template_id: automation.email_template_id, inbox_id: automation.inbox_id,
      sms_provider_id: automation.sms_provider_id,
      subject_jabvox: automation.subject_jabvox, body_jabvox: automation.body_jabvox,
      active_jabvox: automation.active_jabvox,
      start_at_jabvox: automation.start_at_jabvox, end_at_jabvox: automation.end_at_jabvox,
      next_run_at_jabvox: automation.next_run_at_jabvox,
      last_run_at_jabvox: automation.last_run_at_jabvox,
      runs_count_jabvox: automation.runs_count_jabvox
    }.merge(template_fields(automation))
  end

  def template_fields(automation)
    {
      max_runs_jabvox: automation.max_runs_jabvox,
      schedule_mode_jabvox: automation.schedule_mode_jabvox,
      template_name_jabvox: automation.template_name_jabvox,
      template_language_jabvox: automation.template_language_jabvox,
      template_params_jabvox: automation.template_params_jabvox
    }
  end

  def serialize_run(run)
    {
      id: run.id, automation_id: run.automation_id, channel_jabvox: run.channel_jabvox,
      status_jabvox: run.status_jabvox, recipients_count_jabvox: run.recipients_count_jabvox,
      detail_jabvox: run.detail_jabvox, run_at_jabvox: run.run_at_jabvox
    }
  end
end
