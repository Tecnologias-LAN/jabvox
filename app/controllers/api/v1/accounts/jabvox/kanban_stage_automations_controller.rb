class Api::V1::Accounts::Jabvox::KanbanStageAutomationsController < Api::V1::Accounts::Jabvox::BaseController
  jabvox_feature 'jabvox_kanban'
  include JabvoxPermissions

  before_action :ensure_module_permission
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

  # Custom-role gate: users without a custom role keep historical access;
  # users with a custom role must be granted the capability (admins always pass).
  def ensure_module_permission
    jabvox_authorize_write!('jabvox_kanban_manage')
  end

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
      :message_body, :trigger_hours, :target_stage_id, :active,
      :trigger_value_jabvox, :trigger_unit_jabvox,
      :template_name_jabvox, :template_language_jabvox,
      # El mapeo de variables es un hash de forma libre ({"1" => {source:, field:}}), así
      # que se permite entero y el servicio que lo lee valida campo por campo.
      template_params_jabvox: {}
    )
  end
end
