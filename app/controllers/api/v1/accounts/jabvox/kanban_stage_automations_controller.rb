class Api::V1::Accounts::Jabvox::KanbanStageAutomationsController < Api::V1::Accounts::Jabvox::BaseController
  before_action :set_stage
  before_action :set_automation, only: [:show, :update, :destroy]

  def index
    @automations = @stage.jabvox_kanban_stage_automations.order(created_at: :asc)
  end

  def show; end

  def create
    @automation = @stage.jabvox_kanban_stage_automations.create!(
      automation_params.merge(account: Current.account)
    )
    render :show, status: :created
  end

  def update
    @automation.update!(automation_params)
    render :show
  end

  def destroy
    @automation.destroy!
    head :no_content
  end

  private

  def set_stage
    funnel = Current.account.jabvox_kanban_funnels.find(params[:kanban_funnel_id])
    @stage = funnel.jabvox_kanban_stages.find(params[:kanban_stage_id])
  end

  def set_automation
    @automation = @stage.jabvox_kanban_stage_automations.find(params[:id])
  end

  def automation_params
    params.require(:automation).permit(
      :name, :automation_type, :channel_type,
      :inbox_id, :jabvox_email_template_id, :jabvox_sms_provider_id,
      :message_body, :trigger_hours, :target_stage_id, :active
    )
  end
end
