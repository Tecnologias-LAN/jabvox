class Api::V1::Accounts::Jabvox::DialerCampaignsController < Api::V1::Accounts::Jabvox::BaseController # rubocop:disable Metrics/ClassLength
  before_action :check_authorization
  before_action :set_campaign, only: [:show, :update, :destroy, :start, :pause, :stop, :contacts, :call_logs, :retry_contacts]

  def lead_count # rubocop:disable Metrics/AbcSize
    filters = {
      jabvox_campaign_id: params[:jabvox_campaign_id],
      countries: Array(params[:countries]).compact.reject(&:blank?),
      management_state_ids: Array(params[:management_state_ids]).compact.reject(&:blank?),
      affiliate_ids: Array(params[:affiliate_ids]).compact.map(&:to_i).select(&:positive?),
      inbox_ids: Array(params[:inbox_ids]).compact.map(&:to_i).select(&:positive?)
    }
    render json: { count: filter_leads(filters).count }
  end

  def index
    @campaigns = policy_scope(Current.account.jabvox_dialer_campaigns.ordered)
    @live_counts = @campaigns.each_with_object({}) { |c, h| h[c.id] = live_lead_count(c) }
  end

  def show; end

  def create
    @campaign = Current.account.jabvox_dialer_campaigns.new(campaign_params)
    @campaign.save!
    provision_asterisk_queue(@campaign)
    render :show, status: :created
  end

  def update
    @campaign.update!(campaign_params)
    provision_asterisk_queue(@campaign)
    render :show
  end

  def destroy
    @campaign.destroy!
    head :no_content
  end

  def start
    # rubocop:disable Rails/SkipsModelValidations
    @campaign.jabvox_dialer_campaign_contacts
             .where(status_jabvox: 'calling')
             .update_all(status_jabvox: 'failed')
    # rubocop:enable Rails/SkipsModelValidations
    @campaign.update!(status_jabvox: 'active')
    render :show
  end

  def pause
    @campaign.update!(status_jabvox: 'paused')
    render :show
  end

  def stop
    @campaign.update!(status_jabvox: 'completed')
    # rubocop:disable Rails/SkipsModelValidations
    @campaign.jabvox_dialer_campaign_contacts.where(status_jabvox: 'pending').update_all(status_jabvox: 'failed')
    # rubocop:enable Rails/SkipsModelValidations
    render :show
  end

  def retry_contacts
    # rubocop:disable Rails/SkipsModelValidations
    @campaign.jabvox_dialer_campaign_contacts
             .where(status_jabvox: 'calling')
             .update_all(status_jabvox: 'failed')
    # rubocop:enable Rails/SkipsModelValidations
    @campaign.update!(status_jabvox: 'active') unless @campaign.status_jabvox == 'active'
    render :show
  end

  def contacts
    @contacts = @campaign.jabvox_dialer_campaign_contacts.ordered
    render json: @contacts.map { |c| contact_json(c) }
  end

  def call_logs
    @logs = @campaign.jabvox_dialer_call_logs.ordered.limit(200)
    render json: @logs.map { |l| call_log_json(l) }
  end

  def import_contacts # rubocop:disable Metrics/AbcSize
    @campaign = Current.account.jabvox_dialer_campaigns.find(params[:id])
    authorize @campaign
    rows = (params[:contacts] || []).map do |c|
      {
        account_id: Current.account.id,
        jabvox_dialer_campaign_id: @campaign.id,
        name_jabvox: c[:name].to_s,
        phone_jabvox: c[:phone].to_s.strip,
        status_jabvox: 'pending',
        attempts_jabvox: 0
      }
    end
    contacts = rows.select { |c| c[:phone_jabvox].present? }

    # rubocop:disable Rails/SkipsModelValidations
    JabvoxDialerCampaignContact.insert_all!(contacts) if contacts.any?
    # rubocop:enable Rails/SkipsModelValidations
    @campaign.update!(total_contacts_jabvox: @campaign.jabvox_dialer_campaign_contacts.count)
    render json: { imported: contacts.size }
  end

  def originate # rubocop:disable Metrics/AbcSize
    @campaign = Current.account.jabvox_dialer_campaigns.find(params[:id])
    authorize @campaign
    contact = @campaign.jabvox_dialer_campaign_contacts.find(params[:contact_id])
    config = Current.account.jabvox_voip_config

    render json: { success: false, message: 'No VoIP configuration found' }, status: :unprocessable_entity and return if config&.host.blank?

    result = Jabvox::DialerService.new(config).originate_call(
      phone: contact.phone_jabvox,
      extension: params[:extension].to_s,
      caller_id: @campaign.caller_id_jabvox.presence || config.context,
      campaign: @campaign,
      contact: contact,
      account: Current.account
    )
    render json: result
  end

  private

  def provision_asterisk_queue(campaign)
    config = Current.account.jabvox_voip_config
    return unless config&.host.present?

    Jabvox::DialerService.new(config).ensure_queue_exists("dialer_camp_#{campaign.id}")
  rescue StandardError => e
    Rails.logger.warn "⚠️ [Dialer] provision_asterisk_queue failed | campaign=#{campaign.id} error=#{e.message}"
  end

  def set_campaign
    @campaign = Current.account.jabvox_dialer_campaigns.find(params[:id])
  end

  def check_authorization
    authorize @campaign || JabvoxDialerCampaign
  end

  def live_lead_count(campaign)
    filter_leads(
      jabvox_campaign_id: campaign.jabvox_campaign_id,
      countries: (campaign.countries_jabvox || []).map(&:to_s).reject(&:blank?),
      management_state_ids: (campaign.management_state_ids_jabvox || []).map(&:to_s).reject(&:blank?),
      affiliate_ids: (campaign.affiliate_ids_jabvox || []).map(&:to_i).select(&:positive?),
      inbox_ids: (campaign.inbox_ids_jabvox || []).map(&:to_i).select(&:positive?)
    ).count
  rescue StandardError
    campaign.leads_count_jabvox
  end

  def filter_leads(filters) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    leads = Current.account.jabvox_leads.joins(:contact)
    leads = leads.where(jabvox_leads: { jabvox_campaign_id: filters[:jabvox_campaign_id].to_i }) if filters[:jabvox_campaign_id].present?

    countries = filters[:countries]
    if countries.any?
      conds = countries.map { "contacts.additional_attributes->>'country' ILIKE ?" }.join(' OR ')
      leads = leads.where(conds, *countries)
    end

    state_ids = filters[:management_state_ids]
    if state_ids.any?
      include_none = state_ids.include?('none')
      numeric_ids = state_ids.reject { |id| id == 'none' }.map(&:to_i).select(&:positive?)
      state_names = numeric_ids.any? ? Current.account.jabvox_management_states.where(id: numeric_ids).pluck(:name_jabvox) : []
      msgs_base = Current.account.messages.where(private: true)
                         .where("(content_attributes #>> '{}')::json->>'jabvox_management_state_name' IS NOT NULL")
                         .where("(content_attributes #>> '{}')::json->>'jabvox_management_state_name' <> ''")
      contact_ids_with_any_state = Current.account.conversations
                                          .where(id: msgs_base.select(:conversation_id))
                                          .select(:contact_id)
      if state_names.any?
        # Per contact, find the latest (highest ID) management-state message.
        # This ensures we match the LAST gestión, not any historical one.
        latest_per_contact = msgs_base
                               .joins('INNER JOIN conversations ON conversations.id = messages.conversation_id')
                               .unscope(:order)
                               .group('conversations.contact_id')
                               .select('conversations.contact_id, MAX(messages.id) AS max_id')
        name_conds = state_names.map { "((content_attributes #>> '{}')::json->>'jabvox_management_state_name' = ?)" }.join(' OR ')
        contact_ids_matching = Current.account.messages
                                      .joins("INNER JOIN (#{latest_per_contact.to_sql}) lpc ON messages.id = lpc.max_id")
                                      .joins('INNER JOIN conversations ON conversations.id = messages.conversation_id')
                                      .where(name_conds, *state_names)
                                      .select('conversations.contact_id')
        leads = if include_none
                  leads.where("jabvox_leads.contact_id IN (#{contact_ids_matching.to_sql}) OR " \
                              "jabvox_leads.contact_id NOT IN (#{contact_ids_with_any_state.to_sql})")
                else
                  leads.where(contact_id: contact_ids_matching)
                end
      elsif include_none
        leads = leads.where("jabvox_leads.contact_id NOT IN (#{contact_ids_with_any_state.to_sql})")
      end
    end

    affiliate_ids = filters[:affiliate_ids]
    leads = leads.where(jabvox_affiliate_id: affiliate_ids) if affiliate_ids.any?

    inbox_ids = filters[:inbox_ids]
    if inbox_ids.any?
      contact_ids_in_inboxes = Current.account.conversations.where(inbox_id: inbox_ids).select(:contact_id)
      leads = leads.where(contact_id: contact_ids_in_inboxes)
    end

    leads
  end

  def campaign_params
    params.require(:campaign).permit(
      :name_jabvox, :description_jabvox, :status_jabvox,
      :caller_id_jabvox, :max_concurrent_jabvox,
      :retry_count_jabvox, :retry_interval_jabvox,
      :calling_hours_start_jabvox, :calling_hours_end_jabvox,
      :jabvox_campaign_id, :wrapup_time_jabvox, :lines_per_agent_jabvox, :leads_count_jabvox,
      countries_jabvox: [], management_state_ids_jabvox: [], agent_ids_jabvox: [],
      affiliate_ids_jabvox: [], inbox_ids_jabvox: []
    )
  end

  def contact_json(contact)
    {
      id: contact.id, name_jabvox: contact.name_jabvox, phone_jabvox: contact.phone_jabvox,
      status_jabvox: contact.status_jabvox, attempts_jabvox: contact.attempts_jabvox,
      last_attempt_at_jabvox: contact.last_attempt_at_jabvox
    }
  end

  def call_log_json(log)
    {
      id: log.id, phone_jabvox: log.phone_jabvox, status_jabvox: log.status_jabvox,
      duration_jabvox: log.duration_jabvox, started_at_jabvox: log.started_at_jabvox,
      ended_at_jabvox: log.ended_at_jabvox, notes_jabvox: log.notes_jabvox,
      jabvox_dialer_campaign_contact_id: log.jabvox_dialer_campaign_contact_id
    }
  end
end
