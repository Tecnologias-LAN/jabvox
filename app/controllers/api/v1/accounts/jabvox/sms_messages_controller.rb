class Api::V1::Accounts::Jabvox::SmsMessagesController < Api::V1::Accounts::Jabvox::BaseController
  before_action :check_authorization

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
end
