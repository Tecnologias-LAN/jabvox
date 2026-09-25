class Api::V1::Accounts::Jabvox::SmsCampaignsController < Api::V1::Accounts::Jabvox::BaseController
  jabvox_feature 'jabvox_sms'
  include JabvoxPermissions

  before_action :ensure_module_permission
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

  def send_bulk
    provider = @campaign.jabvox_sms_provider
    return render json: { error: 'No active provider configured' }, status: :unprocessable_entity unless provider&.active?

    # Resolvemos los contactos aquí (reusa la lógica de filtrado) pero el ENVÍO se hace en
    # background: encolamos el dispatcher, que hace fan-out de un job por SMS. Así el
    # request no bloquea Puma ni se pierden SMS si el request muere. Devuelve de inmediato.
    contact_ids = resolve_contacts(@campaign).map(&:id)
    @campaign.update!(status: 'queued')
    Jabvox::Sms::DispatchCampaignJob.perform_later(@campaign.id, contact_ids)

    render json: { queued: contact_ids.size, status: 'queued' }
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

  # Gate solo si el usuario tiene un custom role: sin rol personalizado se
  # conserva el comportamiento histórico (acceso). El admin siempre pasa.
  def ensure_module_permission
    jabvox_authorize_write!('jabvox_sms_manage')
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
    leads = Current.account.contacts

    jabvox_cid = filter_params[:jabvox_campaign_id].presence
    leads = leads.where(jabvox_campaign_id: jabvox_cid.to_i) if jabvox_cid

    affiliate_ids = Array(filter_params[:affiliate_ids]).compact.map(&:to_i).select(&:positive?)
    leads = leads.where(jabvox_affiliate_id: affiliate_ids) if affiliate_ids.any?

    inbox_ids = Array(filter_params[:inbox_ids]).compact.map(&:to_i).select(&:positive?)
    if inbox_ids.any?
      contact_ids_in_inboxes = Current.account.conversations
                                      .where(inbox_id: inbox_ids)
                                      .select(:contact_id)
      leads = leads.where(id: contact_ids_in_inboxes)
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
      ).where.not(phone_number: [nil, '']).to_a
    else
      contact_ids = campaign.contact_ids || []
      Current.account.contacts
             .where(id: contact_ids)
             .where.not(phone_number: [nil, ''])
    end
  end
end
