class Api::V1::Accounts::Jabvox::SmsCampaignsController < Api::V1::Accounts::Jabvox::BaseController
  before_action :check_authorization
  before_action :set_campaign, only: [:show, :update, :destroy, :send_bulk]

  def index
    @campaigns = Current.account.jabvox_sms_campaigns
                         .includes(:jabvox_sms_provider)
                         .order(created_at: :desc)
  end

  def show; end

  def create
    @campaign = Current.account.jabvox_sms_campaigns.create!(campaign_params)
    render :show, status: :created
  end

  def update
    @campaign.update!(campaign_params)
    render :show
  end

  def destroy
    @campaign.destroy!
    head :no_content
  end

  def lead_count
    leads = filter_leads(params)
    total = leads.count
    with_phone = leads.joins(:contact)
                      .where.not(contacts: { phone_number: [nil, ''] })
                      .count
    render json: { total_count: total, with_phone_count: with_phone }
  end

  def send_bulk # rubocop:disable Metrics/MethodLength
    provider = @campaign.jabvox_sms_provider
    return render json: { error: 'No active provider configured' }, status: :unprocessable_entity unless provider&.active?

    contacts = resolve_contacts(@campaign)
    queued = 0
    sender = Jabvox::SmsSenderService.new(provider)

    contacts.each do |contact|
      personalized = Jabvox::SmsSenderService.interpolate(@campaign.message, contact)
      sender.send_sms(
        phone: contact.phone_number,
        message: personalized,
        campaign: @campaign,
        contact: contact,
        account: Current.account
      )
      queued += 1
    end

    @campaign.update!(status: 'completed')
    render json: { queued: queued }
  end

  def contacts
    @contacts = Current.account.contacts
                       .where.not(phone_number: [nil, ''])
                       .select(:id, :name, :phone_number, :email)
                       .order(:name)
                       .limit(500)
    render json: @contacts
  end

  private

  def check_authorization
    authorize :jabvox_sms_campaign
  end

  def set_campaign
    @campaign = Current.account.jabvox_sms_campaigns.find(params[:id])
  end

  def campaign_params
    params.require(:campaign).permit(
      :name, :description, :message, :jabvox_sms_provider_id, :status,
      :jabvox_campaign_id,
      contact_ids: [], inbox_ids_sms: [], affiliate_ids_sms: []
    )
  end

  def filter_leads(filter_params) # rubocop:disable Metrics/MethodLength
    leads = Current.account.jabvox_leads

    jabvox_cid = filter_params[:jabvox_campaign_id].presence
    leads = leads.where(jabvox_campaign_id: jabvox_cid.to_i) if jabvox_cid

    affiliate_ids = Array(filter_params[:affiliate_ids]).compact.map(&:to_i).select(&:positive?)
    leads = leads.where(jabvox_affiliate_id: affiliate_ids) if affiliate_ids.any?

    inbox_ids = Array(filter_params[:inbox_ids]).compact.map(&:to_i).select(&:positive?)
    if inbox_ids.any?
      contact_ids_in_inboxes = Current.account.conversations
                                      .where(inbox_id: inbox_ids)
                                      .select(:contact_id)
      leads = leads.where(contact_id: contact_ids_in_inboxes)
    end

    leads
  end

  def resolve_contacts(campaign)
    has_filters = campaign.jabvox_campaign_id.present? ||
                  campaign.inbox_ids_sms.any? ||
                  campaign.affiliate_ids_sms.any?

    if has_filters
      filter_leads(
        jabvox_campaign_id: campaign.jabvox_campaign_id,
        affiliate_ids: campaign.affiliate_ids_sms,
        inbox_ids: campaign.inbox_ids_sms
      ).joins(:contact)
       .where.not(contacts: { phone_number: [nil, ''] })
       .map(&:contact)
    else
      contact_ids = campaign.contact_ids || []
      Current.account.contacts
             .where(id: contact_ids)
             .where.not(phone_number: [nil, ''])
    end
  end
end
