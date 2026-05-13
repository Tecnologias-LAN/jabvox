class Api::V1::Accounts::Jabvox::SmsMessagesController < Api::V1::Accounts::Jabvox::BaseController
  before_action :check_authorization, only: [:index, :stats]

  def send_to_contact
    error = validate_send_params
    return render json: { error: error }, status: :unprocessable_entity if error

    sms = Jabvox::SmsSenderService.new(@sms_provider).send_sms(
      phone: @sms_contact.phone_number,
      message: @sms_message,
      account: Current.account,
      contact: @sms_contact
    )
    render json: { success: sms.status == 'sent', status: sms.status }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def index
    @messages = Current.account.jabvox_sms_messages
                       .includes(:jabvox_sms_campaign, :contact)
                       .order(created_at: :desc)
    @messages = @messages.where(jabvox_sms_campaign_id: params[:campaign_id]) if params[:campaign_id].present?
    @messages = @messages.where(status: params[:status]) if params[:status].present?
    @total = @messages.count
    @messages = @messages.page(params[:page] || 1).per(params[:per] || 20)
  end

  def stats
    msgs = Current.account.jabvox_sms_messages
    render json: {
      total_sent: msgs.where(status: 'sent').count,
      total_failed: msgs.where(status: 'failed').count,
      total_pending: msgs.where(status: 'pending').count
    }
  end

  private

  def check_authorization
    authorize :jabvox_sms_message
  end

  def validate_send_params
    @sms_contact = Current.account.contacts.find(params[:contact_id])
    return 'Contact has no phone number' if @sms_contact.phone_number.blank?

    @sms_provider = Current.account.jabvox_sms_providers.find(params[:provider_id])
    return 'Provider not active' unless @sms_provider.active?

    @sms_message = params[:message].to_s.strip
    'Message is required' if @sms_message.blank?
  end
end
