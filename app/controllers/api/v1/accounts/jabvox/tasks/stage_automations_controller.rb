# Manages the automations attached to a stage (admin only): send_message (inbox/email/sms),
# secure webhook, and time-based moves.
class Api::V1::Accounts::Jabvox::Tasks::StageAutomationsController < Api::V1::Accounts::Jabvox::Tasks::BaseController
  before_action :ensure_admin
  before_action :set_stage
  before_action :set_automation, only: %i[update destroy]

  def index
    render json: @stage.automations.map { |a| serialize(a) }
  end

  def create
    automation = @stage.automations.new(automation_params)
    automation.account = Current.account
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

  private

  def set_stage
    @stage = Current.account.jabvox_task_stages.find(params[:stage_id])
  end

  def set_automation
    @automation = @stage.automations.find(params[:id])
  end

  def automation_params
    params.require(:automation).permit(
      :automation_type_jabvox, :channel_type_jabvox, :message_body_jabvox, :inbox_id,
      :email_template_id, :sms_provider_id, :webhook_url_jabvox, :webhook_secret_jabvox,
      :trigger_hours_jabvox, :target_stage_id, :active_jabvox,
      :trigger_value_jabvox, :trigger_unit_jabvox,
      :template_name_jabvox, :template_language_jabvox,
      # Destinatario: a quién enviar (lead/assignees/manual, por coma) y datos asociados.
      :recipients_jabvox, :manual_email_jabvox, :manual_phone_jabvox,
      # El mapeo de variables es un hash de forma libre ({"1" => {source:, field:}}), así
      # que se permite entero y el servicio que lo lee valida campo por campo.
      template_params_jabvox: {},
      # Mapeo responsable->contacto { "<user_id>" => <contact_id> } para WhatsApp.
      assignee_contact_map_jabvox: {}
    )
  end

  # webhook_secret is write-only (never returned).
  def serialize(automation)
    {
      id: automation.id, automation_type_jabvox: automation.automation_type_jabvox,
      channel_type_jabvox: automation.channel_type_jabvox,
      message_body_jabvox: automation.message_body_jabvox,
      inbox_id: automation.inbox_id, email_template_id: automation.email_template_id,
      sms_provider_id: automation.sms_provider_id, webhook_url_jabvox: automation.webhook_url_jabvox,
      has_webhook_secret: automation.webhook_secret_jabvox.present?,
      trigger_hours_jabvox: automation.trigger_hours_jabvox, target_stage_id: automation.target_stage_id,
      active_jabvox: automation.active_jabvox,
      trigger_value_jabvox: automation.trigger_value_jabvox,
      trigger_unit_jabvox: automation.trigger_unit_jabvox,
      template_name_jabvox: automation.template_name_jabvox,
      template_language_jabvox: automation.template_language_jabvox,
      template_params_jabvox: automation.template_params_jabvox,
      recipients_jabvox: automation.recipients_jabvox,
      manual_email_jabvox: automation.manual_email_jabvox,
      manual_phone_jabvox: automation.manual_phone_jabvox,
      assignee_contact_map_jabvox: automation.assignee_contact_map_jabvox
    }
  end
end
