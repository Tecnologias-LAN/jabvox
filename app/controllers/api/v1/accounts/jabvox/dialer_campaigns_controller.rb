class Api::V1::Accounts::Jabvox::DialerCampaignsController < Api::V1::Accounts::Jabvox::BaseController # rubocop:disable Metrics/ClassLength
  jabvox_feature 'jabvox_dialer'
  include JabvoxPermissions

  before_action :ensure_module_permission
  before_action :check_authorization
  before_action :set_campaign, only: [:show, :update, :destroy, :start, :pause, :stop, :contacts, :call_logs,
                                      :retry_contacts, :report, :progress, :redial_lead, :exclude_lead]

  PREVIEW_PER_PAGE = 25

  def lead_count
    render json: { count: filter_leads(request_filters).count }
  end

  # All lead ids that match the current filters (without exclusions), so the form
  # can "deselect all" (exclude every matching lead) in one call instead of
  # shipping thousands of ids from the client. Capped to avoid a huge payload.
  MATCHING_IDS_LIMIT = 50_000
  def matching_lead_ids
    ids = filter_leads(request_filters.except(:excluded_lead_ids))
          .limit(MATCHING_IDS_LIMIT)
          .pluck('jabvox_leads.id')
    render json: { ids: ids, capped: ids.size >= MATCHING_IDS_LIMIT }
  end

  # Paginated list of the leads the current filters target, so the campaign
  # form can show them and let the admin deselect specific ones.
  def preview_leads
    page = [params[:page].to_i, 1].max
    scope = filter_leads(request_filters.except(:excluded_lead_ids))
            .includes(:contact, :jabvox_campaign)
            .order('jabvox_leads.lead_number ASC')
    total = scope.count
    leads = scope.offset((page - 1) * PREVIEW_PER_PAGE).limit(PREVIEW_PER_PAGE)
    mgmt_by_contact = latest_management_for(leads.filter_map(&:contact_id))
    render json: {
      total: total,
      page: page,
      per_page: PREVIEW_PER_PAGE,
      leads: leads.map { |lead| preview_lead_json(lead, mgmt_by_contact[lead.contact_id]) }
    }
  end

  # The account's lead custom-field definitions, so the campaign form can offer
  # a filter per custom column without depending on the customization module's
  # own endpoints/permissions.
  def lead_fields
    table = Current.account.jabvox_custom_tables.for_leads.first
    columns = table ? table.jabvox_custom_columns.ordered : []
    # Offer every field as a selectable filter: options combine the configured
    # options with the distinct values found in the account's leads (shared
    # helper), so even plain-text fields become checkbox selectors.
    values_by_key = Jabvox::LeadCustomFilter.distinct_values(Current.account, columns.map(&:name_jabvox))
    render json: {
      custom: columns.map do |c|
        configured = Array(c.options_jabvox).map(&:to_s)
        discovered = values_by_key[c.name_jabvox] || []
        { key: c.name_jabvox, label: c.label_jabvox, column_type: c.column_type_jabvox,
          options: (configured + discovered).reject(&:blank?).uniq.sort }
      end
    }
  end

  def index
    @campaigns = policy_scope(Current.account.jabvox_dialer_campaigns.ordered)
    @live_counts = @campaigns.each_with_object({}) { |c, h| h[c.id] = live_lead_count(c) }
  end

  def show; end

  def create
    @campaign = Current.account.jabvox_dialer_campaigns.new(campaign_params)
    @campaign.save!
    sync_leads_count(@campaign)
    provision_asterisk_queue(@campaign)
    render :show, status: :created
  end

  def update
    @campaign.update!(campaign_params)
    sync_leads_count(@campaign)
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

  # One-by-one progress: how many leads total match the campaign, how many have
  # been dialed, how many are left to dial (fresh), and how many are queued for a
  # retry. Lets the UI show "marcados / faltan".
  def progress
    ccs         = @campaign.jabvox_dialer_campaign_contacts
    contacts_ct = ccs.count
    # A campaign only materializes campaign_contacts once it starts dialing. Before
    # that (draft/paused, never activated) there are 0 contacts, so fall back to the
    # count of leads that MATCH the campaign filters — otherwise the card shows 0
    # leads even though hundreds match. Once dialing begins, use the contact count.
    total = contacts_ct.positive? ? contacts_ct : live_lead_count(@campaign)
    # "Dialed" = leads with at least one call log OR attempts>0 (same source of
    # truth as the report, so the card and the report never disagree).
    dialed   = dialed_contact_ids.size
    retry_st = Array(@campaign.retry_statuses_jabvox)
    pending_retry = retry_st.any? ? ccs.where(status_jabvox: retry_st).count : 0
    # Answered = distinct leads with an answered call log OR a completed contact.
    answered_log_ids = @campaign.jabvox_dialer_call_logs
                                .where(status_jabvox: 'answered')
                                .or(@campaign.jabvox_dialer_call_logs.where(lead_answered_jabvox: true))
                                .distinct.pluck(:jabvox_dialer_campaign_contact_id).compact
    completed_ids = ccs.where(status_jabvox: 'completed').pluck(:id)
    answered = (answered_log_ids + completed_ids).uniq.size
    render json: {
      total: total,
      dialed: dialed,
      remaining: [total - dialed, 0].max, # fresh leads not yet dialed
      pending_retry: pending_retry,
      answered: answered
    }
  end

  # Re-queue an already-dialed lead so it enters the campaign again: reset its
  # campaign-contact back to 'pending' (or delete the row so it's treated as
  # fresh). Used from the "volver a marcar" action on a contact.
  def redial_lead
    contact_id = params[:contact_id].to_i
    cc = @campaign.jabvox_dialer_campaign_contacts.find_by(contact_id: contact_id)
    return render json: { error: 'Contacto no encontrado en la campaña' }, status: :not_found unless cc

    # Delete the row → the picker treats the lead as fresh again (goes to the
    # front of the one-by-one queue by lead id). attempts reset with it.
    cc.destroy!
    render json: { ok: true }
  end

  # "No marcar": exclude the lead from the campaign so the dialer never calls it.
  # Adds its jabvox_lead id to excluded_lead_ids_jabvox and removes its pending
  # campaign-contact row, so it leaves the "sin marcar" list. Reversible from the
  # campaign form. Respects the campaign config: an excluded lead is skipped by the
  # picker/filter regardless of dial mode (last_state or one_by_one).
  def exclude_lead
    contact_id = params[:contact_id].to_i
    lead = Current.account.jabvox_leads.find_by(contact_id: contact_id)
    return render json: { error: 'Lead no encontrado' }, status: :not_found unless lead

    excluded = Array(@campaign.excluded_lead_ids_jabvox).map(&:to_i)
    excluded << lead.id unless excluded.include?(lead.id)
    @campaign.update!(excluded_lead_ids_jabvox: excluded.uniq)

    # Drop any not-yet-dialed campaign-contact row so it disappears from "sin
    # marcar" immediately (only if it has no call log — never touch dialed leads).
    cc = @campaign.jabvox_dialer_campaign_contacts.find_by(contact_id: contact_id)
    cc.destroy! if cc && !dialed_contact_ids.include?(cc.id)
    render json: { ok: true }
  end

  def call_logs
    @logs = @campaign.jabvox_dialer_call_logs.ordered.limit(200)
    render json: @logs.map { |l| call_log_json(l) }
  end

  def report # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    tz         = 'America/Bogota'
    from_date  = parse_report_date(params[:from], 7.days.ago.beginning_of_day).beginning_of_day
    to_date    = parse_report_date(params[:to], Time.current.end_of_day).end_of_day + 1.second
    group_by   = params[:group_by] == 'hour' ? 'hour' : 'day'
    period_sql = "DATE_TRUNC('#{group_by}', started_at_jabvox AT TIME ZONE '#{tz}')"

    base = @campaign.jabvox_dialer_call_logs
                    .where.not(started_at_jabvox: nil)
                    .where(started_at_jabvox: from_date...to_date)

    if params[:from_hour].present? && params[:to_hour].present?
      from_h = params[:from_hour].to_i.clamp(0, 23)
      to_h   = params[:to_hour].to_i.clamp(0, 23)
      base   = base.where(
        'EXTRACT(HOUR FROM started_at_jabvox AT TIME ZONE ?) >= ? AND ' \
        'EXTRACT(HOUR FROM started_at_jabvox AT TIME ZONE ?) <= ?',
        tz, from_h, tz, to_h
      )
    end

    select_cols = [
      Arel.sql(period_sql),
      Arel.sql('COUNT(*)'),
      Arel.sql("COUNT(*) FILTER (WHERE status_jabvox = 'answered')"),
      Arel.sql("COUNT(*) FILTER (WHERE status_jabvox != 'answered' AND NOT COALESCE(lead_answered_jabvox, false))"),
      Arel.sql("COUNT(*) FILTER (WHERE status_jabvox != 'answered' AND COALESCE(lead_answered_jabvox, false))"),
      Arel.sql('COUNT(DISTINCT agent_id_jabvox) FILTER (WHERE agent_id_jabvox IS NOT NULL)')
    ]

    rows    = base.group(Arel.sql(period_sql)).order(Arel.sql(period_sql)).pluck(*select_cols)
    tot_row = base.pluck(*select_cols.drop(1)).first || Array.new(5, 0)

    # Fallback: leads dialed WITHOUT a usable call log (log never created or its
    # timestamp is missing) still count via the campaign-contacts, so a managed
    # campaign is never reported as empty. Uses last_attempt_at within the range.
    contacts = dialed_contacts_without_log(from_date, to_date)

    totals = {
      total: tot_row[0], answered: tot_row[1], no_answer: tot_row[2],
      no_agent: tot_row[3], agents: tot_row[4]
    }
    merge_contact_totals!(totals, contacts)

    # Whole-campaign lead counts (independent of the date range), so the summary
    # always shows how many leads there are, how many were dialed and how many are
    # still pending — the "leads sin marcar y marcados" the user wants to see.
    counts = campaign_lead_counts
    totals[:leads_total]   = counts[:total]
    totals[:leads_dialed]  = counts[:dialed]
    totals[:leads_pending] = counts[:pending]

    render json: {
      rows: rows.map { |r| { period: r[0], total: r[1], answered: r[2], no_answer: r[3], no_agent: r[4], agents: r[5] } },
      totals: totals,
      calls: report_call_details(base, tz) + contact_call_rows(contacts, tz),
      leads: report_lead_summary(base, tz, contacts),
      pending: pending_lead_rows
    }
  end

  # A campaign-contact is "dialed" if it has at least one call log OR its
  # attempts counter is > 0. Using the call logs as the source of truth fixes the
  # inconsistency where a lead had calls but attempts_jabvox stayed 0 (one-by-one
  # / predictive flows don't always bump the counter), so the report showed it as
  # "sin marcar" despite having 8 calls.
  def dialed_contact_ids
    @dialed_contact_ids ||= begin
      with_logs = @campaign.jabvox_dialer_call_logs
                           .distinct.pluck(:jabvox_dialer_campaign_contact_id)
                           .compact
      with_attempts = @campaign.jabvox_dialer_campaign_contacts
                               .where('attempts_jabvox > 0').pluck(:id)
      (with_logs + with_attempts).uniq
    end
  end

  # Campaign-wide lead counts (all time): total, dialed, pending.
  def campaign_lead_counts
    total = @campaign.jabvox_dialer_campaign_contacts.count
    dialed = dialed_contact_ids.size
    { total: total, dialed: dialed, pending: [total - dialed, 0].max }
  end

  # Leads not dialed yet (pending = no call log AND no attempts), so the summary
  # lists "sin marcar" too.
  REPORT_PENDING_LIMIT = 2000
  def pending_lead_rows
    @campaign.jabvox_dialer_campaign_contacts
             .includes(:contact)
             .where.not(id: dialed_contact_ids)
             .order(:id)
             .limit(REPORT_PENDING_LIMIT)
             .map do |cc|
      {
        contact_id: cc.contact_id,
        lead_name: cc.name_jabvox.presence || cc.contact&.name.to_s,
        phone: cc.phone_jabvox,
        status: cc.status_jabvox
      }
    end
  end

  # Campaign-contacts that were dialed within the window but have NO call log in
  # `base` (log missing / timestamp null). Uses attempts>0 as the marker; contacts
  # that already have a call log are surfaced through the logs themselves.
  def dialed_contacts_without_log(from_date, to_date)
    logged_ids = @campaign.jabvox_dialer_call_logs
                          .where.not(started_at_jabvox: nil)
                          .distinct.pluck(:jabvox_dialer_campaign_contact_id)
    @campaign.jabvox_dialer_campaign_contacts
             .includes(:contact)
             .where('attempts_jabvox > 0')
             .where(last_attempt_at_jabvox: from_date...to_date)
             .where.not(id: logged_ids.compact)
             .to_a
  end

  # A campaign-contact status maps to answered when completed, else no-answer.
  def contact_answered?(cc)
    cc.status_jabvox == 'completed'
  end

  def merge_contact_totals!(totals, contacts)
    return if contacts.empty?

    answered = contacts.count { |cc| contact_answered?(cc) }
    totals[:total]     += contacts.size
    totals[:answered]  += answered
    totals[:no_answer] += contacts.size - answered
    # These contacts have no agent on record → count toward "sin agente".
    totals[:no_agent]  += contacts.size - answered
  end

  # Per-lead summary: who was dialed, how many times, last status/agent/time.
  # Groups the call logs by the campaign-contact so the report can show one row
  # per lead with its attempt count — what the agent asked to see. `extra_contacts`
  # are dialed leads with no call log; they're appended so the summary is complete.
  REPORT_LEADS_LIMIT = 2000
  def report_lead_summary(base, tz, extra_contacts = [])
    logs = base.includes(jabvox_dialer_campaign_contact: :contact)
               .order(started_at_jabvox: :desc)
    by_contact = logs.group_by(&:jabvox_dialer_campaign_contact_id)
    agent_ids  = logs.filter_map(&:agent_id_jabvox).uniq
    agent_names = User.where(id: agent_ids).pluck(:id, :name).to_h

    summaries = by_contact.map do |_cc_id, cc_logs|
      last = cc_logs.first # newest first (ordered above)
      cc   = last.jabvox_dialer_campaign_contact
      answered_count = cc_logs.count { |l| l.status_jabvox == 'answered' || l.lead_answered_jabvox }
      {
        contact_id: cc&.contact_id,
        lead_name: cc&.name_jabvox.presence || cc&.contact&.name.to_s,
        phone: last.phone_jabvox,
        attempts: cc_logs.size,
        answered_count: answered_count,
        last_status: last.status_jabvox,
        last_answered: last.lead_answered_jabvox,
        last_agent: agent_names[last.agent_id_jabvox],
        last_called_at: last.started_at_jabvox&.in_time_zone(tz)&.iso8601
      }
    end

    summaries += extra_contacts.map do |cc|
      answered = contact_answered?(cc)
      {
        contact_id: cc.contact_id,
        lead_name: cc.name_jabvox.presence || cc.contact&.name.to_s,
        phone: cc.phone_jabvox,
        attempts: cc.attempts_jabvox.to_i,
        answered_count: answered ? 1 : 0,
        last_status: answered ? 'answered' : cc.status_jabvox,
        last_answered: answered,
        last_agent: nil,
        last_called_at: cc.last_attempt_at_jabvox&.in_time_zone(tz)&.iso8601
      }
    end
    summaries.sort_by { |s| -s[:attempts] }.first(REPORT_LEADS_LIMIT)
  end

  # Per-call rows for dialed contacts without a call log, so they appear in the
  # detail table too (state from the campaign-contact status).
  def contact_call_rows(contacts, tz)
    contacts.map do |cc|
      answered = contact_answered?(cc)
      {
        contact_id: cc.contact_id,
        lead_name: cc.name_jabvox.presence || cc.contact&.name.to_s,
        phone: cc.phone_jabvox,
        agent_name: nil,
        status: answered ? 'answered' : cc.status_jabvox,
        answered: answered,
        called_at: cc.last_attempt_at_jabvox&.in_time_zone(tz)&.iso8601,
        duration: nil
      }
    end
  end

  # Per-call detail for the report: who was dialed (lead name + phone), which
  # agent dialed, when, and the outcome. Capped so a huge campaign never returns
  # an unbounded payload; newest first.
  REPORT_CALLS_LIMIT = 1000
  def report_call_details(base, tz)
    logs = base.includes(jabvox_dialer_campaign_contact: :contact)
               .order(started_at_jabvox: :desc)
               .limit(REPORT_CALLS_LIMIT)
    agent_names = User.where(id: logs.filter_map(&:agent_id_jabvox).uniq).pluck(:id, :name).to_h
    logs.map do |l|
      cc = l.jabvox_dialer_campaign_contact
      {
        contact_id: cc&.contact_id, # lets the UI re-queue this lead ("volver a marcar")
        lead_name: cc&.name_jabvox.presence || cc&.contact&.name.to_s,
        phone: l.phone_jabvox,
        agent_name: agent_names[l.agent_id_jabvox],
        status: l.status_jabvox,
        answered: l.lead_answered_jabvox,
        called_at: l.started_at_jabvox&.in_time_zone(tz)&.iso8601,
        duration: l.duration_jabvox
      }
    end
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
      account: Current.account,
      # One-by-one dialing is done BY the current agent. Persist who dialed so the
      # call log carries agent_id_jabvox and the channel carries JABVOX_AGENT_USER_ID
      # — without this the report can't attribute the call and shows 0 answered.
      user_id: Current.user&.id
    )
    render json: result
  end

  private

  def provision_asterisk_queue(campaign)
    config = Current.account.jabvox_voip_config
    return unless config&.host.present?

    Jabvox::DialerService.new(config).ensure_queue_exists(
      "dialer_camp_#{campaign.id}",
      wait_in_queue: campaign.wait_in_queue_jabvox
    )
  rescue StandardError => e
    Rails.logger.warn "⚠️ [Dialer] provision_asterisk_queue failed | campaign=#{campaign.id} error=#{e.message}"
  end

  def parse_report_date(value, fallback)
    return fallback if value.blank?

    # Time.zone.parse returns nil (not an exception) for garbage like "basura",
    # so guard against nil too or `.beginning_of_day` downstream would 500.
    Time.zone.parse(value) || fallback
  rescue StandardError
    fallback
  end

  def set_campaign
    @campaign = Current.account.jabvox_dialer_campaigns.find(params[:id])
  end

  def check_authorization
    authorize @campaign || JabvoxDialerCampaign
  end

  # Gate solo si el usuario tiene un custom role: sin rol personalizado se
  # conserva el comportamiento histórico (acceso). El admin siempre pasa.
  def ensure_module_permission
    jabvox_authorize_write!('jabvox_dialer_manage')
  end

  def live_lead_count(campaign)
    Jabvox::DialerLeadsFilterService.for_campaign(Current.account, campaign).scope.count
  rescue StandardError
    campaign.leads_count_jabvox
  end

  # Recompute and persist leads_count_jabvox from the real matching count after a
  # save, so the stored count is never a stale 0 from the client. Fully defensive:
  # any failure here must NEVER break the campaign save (which already succeeded).
  def sync_leads_count(campaign)
    count = live_lead_count(campaign)
    return unless count.is_a?(Integer) && count != campaign.leads_count_jabvox

    campaign.update_columns(leads_count_jabvox: count) # rubocop:disable Rails/SkipsModelValidations
  rescue StandardError => e
    Rails.logger.warn "[Dialer] sync_leads_count failed | campaign=#{campaign.id} error=#{e.message}"
  end

  # Normalized filters from query/body params — same shape the service accepts.
  def request_filters
    {
      jabvox_campaign_id: params[:jabvox_campaign_id],
      countries: Array(params[:countries]).compact.reject(&:blank?),
      management_state_ids: Array(params[:management_state_ids]).compact.reject(&:blank?),
      affiliate_ids: Array(params[:affiliate_ids]).compact.map(&:to_i).select(&:positive?),
      inbox_ids: Array(params[:inbox_ids]).compact.map(&:to_i).select(&:positive?),
      q: params[:q].to_s,
      email: params[:email].to_s,
      phone: params[:phone].to_s,
      custom: custom_filters_param,
      excluded_lead_ids: Array(params[:excluded_lead_ids]).map(&:to_i).select(&:positive?)
    }
  end

  # Dynamic custom-field filters arrive as custom[key]=value; only string
  # values pass through (keys are slug-sanitized inside the filter service).
  def custom_filters_param
    raw = params[:custom]
    raw = raw.permit!.to_h if raw.respond_to?(:permit!)
    return {} unless raw.is_a?(Hash)

    # Return the hash as-is: values keep their shape (String for substring match,
    # Array / index-Hash for multi-select incl. axios's [0][1] form). The shared
    # Jabvox::LeadCustomFilter handles and sanitizes every shape — flattening to
    # strings here would break list filters.
    raw
  end

  def preview_lead_json(lead, last_management_state = nil)
    contact = lead.contact
    {
      id: lead.id,
      lead_number: lead.lead_number,
      name: contact&.name.to_s,
      phone: contact&.phone_number.to_s,
      email: contact&.email.to_s,
      campaign: lead.jabvox_campaign&.name_jabvox.to_s,
      document: lead_document(lead, contact),
      last_management_state: last_management_state.to_s
    }
  end

  # Latest gestión (management-state private note) per contact for one page of
  # leads — same definition the leads list uses.
  def latest_management_for(contact_ids)
    ids = contact_ids.map(&:to_i).select(&:positive?)
    return {} if ids.empty?

    sql = <<~SQL.squish
      SELECT DISTINCT ON (c.contact_id) c.contact_id,
        (m.content_attributes #>> '{}')::json->>'jabvox_management_state_name' AS last_management_state
      FROM conversations c
      JOIN messages m ON m.conversation_id = c.id
      WHERE c.account_id = #{Current.account.id.to_i}
        AND c.contact_id IN (#{ids.join(', ')})
        AND m.private = true
        AND (m.content_attributes #>> '{}')::json->>'jabvox_management_state_name' IS NOT NULL
        AND (m.content_attributes #>> '{}')::json->>'jabvox_management_state_name' <> ''
      ORDER BY c.contact_id, m.created_at DESC
    SQL
    ApplicationRecord.connection.execute(sql)
                     .each_with_object({}) { |r, h| h[r['contact_id'].to_i] = r['last_management_state'] }
  end

  # "Documento": custom field first (documento/document/cedula/dni/nit),
  # then the contact identifier.
  def lead_document(lead, contact)
    custom = lead.custom_fields_jabvox || {}
    %w[documento document cedula dni nit].each do |key|
      value = custom[key].to_s
      return value if value.present?
    end
    contact&.identifier.to_s
  end

  def filter_leads(filters)
    Jabvox::DialerLeadsFilterService.new(Current.account, filters).scope
  end

  def campaign_params
    permitted = params.require(:campaign).permit(
      :name_jabvox, :description_jabvox, :status_jabvox,
      :caller_id_jabvox, :max_concurrent_jabvox,
      :retry_count_jabvox, :retry_interval_jabvox,
      :calling_hours_start_jabvox, :calling_hours_end_jabvox,
      :schedule_start_date_jabvox, :schedule_end_date_jabvox,
      :jabvox_campaign_id, :wrapup_time_jabvox, :lines_per_agent_jabvox, :leads_count_jabvox,
      :wait_in_queue_jabvox, :dial_mode_jabvox, :dial_field_jabvox, :dial_prefix_jabvox,
      :max_retries_jabvox,
      countries_jabvox: [], management_state_ids_jabvox: [], agent_ids_jabvox: [],
      affiliate_ids_jabvox: [], inbox_ids_jabvox: [], excluded_lead_ids_jabvox: [],
      retry_statuses_jabvox: []
    )
    if permitted.key?(:excluded_lead_ids_jabvox)
      permitted[:excluded_lead_ids_jabvox] =
        permitted[:excluded_lead_ids_jabvox].map(&:to_i).select(&:positive?)
    end
    permitted.merge(lead_filters_jabvox: lead_filters_param)
  end

  # lead_filters_jabvox has dynamic custom keys, so it can't go through a
  # static permit list; whitelist its shape by hand instead.
  def lead_filters_param
    raw = params.dig(:campaign, :lead_filters_jabvox)
    return {} if raw.blank?

    raw = raw.permit!.to_h if raw.respond_to?(:permit!)
    return {} unless raw.is_a?(Hash)

    {
      'q' => raw['q'].to_s,
      'email' => raw['email'].to_s,
      'phone' => raw['phone'].to_s,
      'custom' => normalize_custom_filters(raw['custom'])
    }.reject { |k, v| k != 'custom' && v.blank? }
  end

  # Preserve the SHAPE of each custom filter so multiselect (Array / index-Hash)
  # keeps matching after save. Flattening arrays to strings (.to_s) turned
  # ["121"] into the literal "[\"121\"]", which never matched -> 0 leads on edit
  # / activate even though the live count showed results. Drops blank/empty
  # filters; keeps strings, arrays and axios's index-hash form intact.
  def normalize_custom_filters(custom)
    return {} unless custom.is_a?(Hash)

    custom.each_with_object({}) do |(key, value), acc|
      normalized =
        case value
        when Array then value.map(&:to_s).reject(&:blank?)
        when Hash  then value.values.map(&:to_s).reject(&:blank?) # axios [0][1] form
        else value.to_s
        end
      next if normalized.blank? # skips "" and []

      acc[key.to_s] = normalized
    end
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
