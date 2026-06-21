class Api::V1::Accounts::Jabvox::WhatsappTemplates::InboxesController < Api::V1::Accounts::Jabvox::WhatsappTemplates::BaseController
  def index
    inboxes = Current.account.inboxes
                     .joins("INNER JOIN channel_whatsapp ON inboxes.channel_id = channel_whatsapp.id AND inboxes.channel_type = 'Channel::Whatsapp'")
                     .where("channel_whatsapp.provider = 'whatsapp_cloud'")
    render json: { inboxes: inboxes.map { |i| serialize_inbox(i) } }
  end

  def sync
    inbox = Current.account.inboxes.find(params[:inbox_id])
    result = manager.sync_inbox(inbox)
    if result[:success]
      render json: result
    else
      render json: { error: result[:error] }, status: :unprocessable_entity
    end
  end

  def metrics
    render json: manager.metrics(inbox_id: params[:inbox_id])
  end

  private

  def serialize_inbox(inbox)
    ch = inbox.channel
    {
      id: inbox.id,
      name: inbox.name,
      phone_number: ch.phone_number,
      waba_id: ch.provider_config['business_account_id'],
      last_synced: ch.message_templates_last_updated,
      template_count: Current.account.jabvox_whatsapp_templates.where(inbox_id: inbox.id).count
    }
  end
end
