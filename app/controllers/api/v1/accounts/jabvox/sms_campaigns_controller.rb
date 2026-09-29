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

  # Cuántos contactos alcanzaría la campaña con los filtros actuales, y de ésos cuántos
  # tienen teléfono (los únicos a los que se les puede mandar un SMS).
  #
  # El teléfono está en el propio contacto. Antes esto hacía `joins(:contact)` porque
  # filtraba leads, y cada lead colgaba de un contacto; al pasar a contactos esa asociación
  # dejó de existir y la consulta reventaba con 500.
  def lead_count
    contacts = filter_contacts(params)
    render json: { total_count: contacts.count,
                   with_phone_count: contacts.where.not(phone_number: [nil, '']).count }
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

  # Los tres filtros del formulario de campaña, cada uno opcional: campaña comercial,
  # afiliados y bandejas. Un filtro ausente no restringe nada.
  def filter_contacts(filter_params)
    contacts = Current.account.contacts
    contacts = by_campaign(contacts, filter_params[:jabvox_campaign_id])
    contacts = by_affiliates(contacts, filter_params[:affiliate_ids])
    by_inboxes(contacts, filter_params[:inbox_ids])
  end

  def by_campaign(scope, campaign_id)
    campaign_id.presence ? scope.where(jabvox_campaign_id: campaign_id.to_i) : scope
  end

  def by_affiliates(scope, affiliate_ids)
    ids = positive_ids(affiliate_ids)
    ids.any? ? scope.where(jabvox_affiliate_id: ids) : scope
  end

  # Contactos que tienen al menos una conversación en alguna de las bandejas elegidas.
  def by_inboxes(scope, inbox_ids)
    ids = positive_ids(inbox_ids)
    return scope if ids.empty?

    scope.where(id: Current.account.conversations.where(inbox_id: ids).select(:contact_id))
  end

  def positive_ids(values)
    Array(values).compact.map(&:to_i).select(&:positive?)
  end

  def resolve_contacts(campaign)
    has_filters = campaign.jabvox_campaign_id.present? ||
                  campaign.inbox_ids_sms.any? ||
                  campaign.affiliate_ids_sms.any?

    if has_filters
      filter_contacts(
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
