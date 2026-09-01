class Api::V1::Accounts::Jabvox::LeadsController < Api::V1::Accounts::BaseController
  include JabvoxPermissions

  before_action :check_leads_enabled
  # Custom-role gates: only enforced when the user has a custom role assigned, so plain
  # agents/admins keep their historical behavior (admins always pass via jabvox_gate!).
  before_action -> { jabvox_gate!('jabvox_leads_assign') }, only: %i[bulk_assign bulk_unassign]
  # Deleting leads is controlled from Super Admin (per-account module) and is
  # restricted to administrators only — never agents nor custom roles.
  before_action :check_lead_delete_allowed, only: :bulk_destroy
  # update_details NO se gatea por permiso: todo el que puede VER un lead (leads,
  # contactos, detalle) puede editarlo, sin importar su rol. jabvox_leads_edit
  # queda reservado para restricciones futuras de acciones masivas.

  PER_PAGE_OPTIONS = [10, 25, 50, 100, 200, 250].freeze
  DEFAULT_PER_PAGE = 25
  SORTABLE_COLUMNS = {
    'lead_number' => 'jabvox_leads.lead_number',
    'created_at' => 'jabvox_leads.created_at',
    'name' => 'contacts.name',
    'email' => 'contacts.email',
    'phone_number' => 'contacts.phone_number'
  }.freeze

  def index
    per_page = PER_PAGE_OPTIONS.include?(params[:per_page].to_i) ? params[:per_page].to_i : DEFAULT_PER_PAGE
    filter_scope = build_filter_scope
    @total = filter_scope.count
    @leads = filter_scope.includes(:contact, :jabvox_campaign, :assignee, :jabvox_affiliate).page(params[:page] || 1).per(per_page)
    @conv_data = load_conversation_data(@leads.map(&:contact_id))
    load_management_history(@leads)
    # Filter options are static per session (management states, campaigns, inboxes,
    # teams, assignees, affiliates) — 6 extra queries. Only build them on the first
    # page (or when explicitly requested) so paginating/searching stays fast; the
    # frontend keeps its cached copy for later pages.
    @filter_options = build_filter_options if include_filter_options?
  end

  # Returns ALL lead ids matching the current filters (not just the page), so the
  # UI can "select the whole filter" and bulk-assign hundreds of leads at once.
  # Respects the exact same scoping as the list (role/permission + filters), so an
  # agent can only ever select the leads they may see. Capped to avoid an
  # unbounded payload; `capped` tells the UI it hit the limit.
  MATCHING_IDS_LIMIT = 20_000
  def matching_lead_ids
    ids = build_filter_scope.limit(MATCHING_IDS_LIMIT).pluck('jabvox_leads.id')
    render json: { ids: ids, total: ids.size, capped: ids.size >= MATCHING_IDS_LIMIT }
  end

  def show
    @lead = Current.account.jabvox_leads.includes(:contact, :jabvox_campaign, :assignee, :jabvox_affiliate).find(params[:id])
    @conv_data = (load_conversation_data([@lead.contact_id]))[@lead.contact_id] || {}
  end

  def for_contact
    lead = Current.account.jabvox_leads
                  .includes(:jabvox_campaign, :jabvox_affiliate, :assignee, :contact)
                  .find_by(contact_id: params[:contact_id])
    render json: {
      id: lead&.id,
      campaign_id: lead&.jabvox_campaign_id,
      campaign_name: lead&.jabvox_campaign&.name_jabvox,
      # Flat field map (default + custom) so the WhatsApp template composer can
      # auto-fill {{n}} variables from this contact/lead. Custom fields are
      # prefixed "custom:" to mirror the bulk sender.
      fields: lead_template_fields(lead),
      # Every custom field DEFINED for the account (key + label), so the 1-to-1
      # composer can offer all of them as variable sources — without hitting the
      # admin-only bulk endpoint. Accessible to agents, same as this action.
      custom_field_defs: lead_custom_field_defs
    }
  end

  # Full lead detail for one contact (contact fields + lead fields + inbox +
  # custom lead fields), mirroring the lead detail page. Used by the conversation
  # sidebar's "Información del lead" panel. Available to any agent who can see
  # leads — NOT gated by the reports permission.
  def lead_detail
    result = Jabvox::LeadDetailPresenter.new(
      account: Current.account, contact_id: params[:contact_id]
    ).call
    return render(json: { error: 'Lead no encontrado' }, status: :not_found) unless result

    render json: result
  end

  def update_contact_lead
    lead = JabvoxLead.find_or_initialize_by(account: Current.account, contact_id: params[:contact_id].to_i)
    lead.jabvox_campaign = find_or_create_campaign(params[:campaign_name])
    lead.save!
    render json: { id: lead.id, campaign_id: lead.jabvox_campaign_id, campaign_name: lead.jabvox_campaign&.name_jabvox }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Crea el JabvoxLead que falte para cada contacto de la cuenta. Inserción masiva
  # en lotes (no N+1): una query para los contact_id sin lead y insert_all por lote.
  def sync_contacts
    account = Current.account
    existing = JabvoxLead.where(account_id: account.id).select(:contact_id)
    missing_ids = account.contacts.where.not(id: existing).pluck(:id)
    render(json: { synced: 0 }) and return if missing_ids.empty?

    next_number = (JabvoxLead.where(account_id: account.id).maximum(:lead_number) || 0) + 1
    synced = insert_missing_leads(account.id, missing_ids, next_number)
    render json: { synced: synced }
  end

  def bulk_assign
    assignee = Current.account.users.find(params[:assignee_id])
    leads = Current.account.jabvox_leads.where(id: params[:lead_ids])
    count = leads.count
    leads.update_all(assignee_id: assignee.id)
    # Keep the contacts' open conversations owned by the same agent.
    Jabvox::LeadConversationAssignmentSync.new(Current.account).sync_leads(leads.to_a, assignee)
    ActionCable.server.broadcast(
      "account_#{Current.account.id}",
      {
        event: 'jabvox.leads_assigned',
        data: {
          account_id: Current.account.id,
          assignee_id: assignee.id,
          count: count
        }
      }
    )
    render json: { assigned: count }
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'User not found' }, status: :not_found
  end

  def bulk_unassign
    leads = Current.account.jabvox_leads.where(id: params[:lead_ids])
    count = leads.count
    leads.update_all(assignee_id: nil)
    render json: { unassigned: count }
  end

  def bulk_destroy
    leads = Current.account.jabvox_leads.where(id: params[:lead_ids])
    contact_ids = leads.pluck(:contact_id).compact
    count = leads.count
    return render json: { deleted: 0 } if count.zero?

    # Snapshot to the restorable trash before deleting, so leads are never lost.
    Jabvox::LeadImport::TrashService.new(Current.account)
                                    .snapshot_leads(leads.includes(:contact).to_a,
                                                    origin: 'bulk_delete', deleted_by: current_user)

    lead_ids = leads.pluck(:id)
    JabvoxKanbanConversationStage.where(jabvox_lead_id: lead_ids).delete_all
    # Clear every child FK before delete_all (which skips model callbacks):
    # call logs and tasks keep their history detached; join/source rows go away.
    # rubocop:disable Rails/SkipsModelValidations
    JabvoxCallLog.where(jabvox_lead_id: lead_ids).update_all(jabvox_lead_id: nil)
    JabvoxTask.where(jabvox_lead_id: lead_ids).update_all(jabvox_lead_id: nil)
    # rubocop:enable Rails/SkipsModelValidations
    JabvoxTaskLeadContact.where(jabvox_lead_id: lead_ids).delete_all
    JabvoxLeadSourceRecord.where(jabvox_lead_id: lead_ids).delete_all
    JabvoxCustomTableRow.where(jabvox_lead_id: lead_ids).delete_all
    Current.account.jabvox_leads.where(id: lead_ids).delete_all

    contact_ids.each do |contact_id|
      contact = Current.account.contacts.find_by(id: contact_id)
      next unless contact

      conv_ids = contact.conversations.select(:id)
      JabvoxKanbanConversationStage.where(conversation_id: conv_ids).delete_all
      JabvoxCalendarEvent.where(contact_id: contact_id).delete_all
      JabvoxSmsMessage.where(contact_id: contact_id).delete_all
      contact.destroy!
    end

    render json: { deleted: count }
  end

  def custom_fields
    lead = Current.account.jabvox_leads.find(params[:id])
    result = sanitize_custom_fields(lead)
    return render json: { error: result.errors.join(', ') }, status: :unprocessable_entity unless result.valid?

    lead.update!(custom_fields_jabvox: result.data)
    render json: { id: lead.id, custom_fields_jabvox: lead.custom_fields_jabvox }
  end

  # Unified edit for the lead detail panel: contact fields (phone/email/country),
  # campaign, assignee and custom fields — all in one transaction.
  def update_details
    lead = Current.account.jabvox_leads.find(params[:id])
    ActiveRecord::Base.transaction do
      update_contact_fields(lead)
      update_assignee(lead)
      update_campaign(lead)
      update_custom_fields(lead)
    end
    render json: { id: lead.id }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  # Assigns the lead (and its open conversations) to the current agent. Called
  # after sending a WhatsApp template from the lead detail so lead + contact +
  # conversation all end up owned by whoever started the chat — otherwise the
  # conversation stays unassigned/owned by someone else and agents (who only see
  # their own) can't find it in Conversations.
  def claim
    lead = Current.account.jabvox_leads.find(params[:id])
    lead.update!(assignee_id: current_user.id)
    synced = Jabvox::LeadConversationAssignmentSync.new(Current.account).sync_lead(lead, current_user)
    render json: { id: lead.id, assignee_id: current_user.id, conversations_synced: synced }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  private

  # unique_by (account_id, contact_id) hace la inserción idempotente ante una carrera.
  def insert_missing_leads(account_id, missing_ids, next_number)
    now = Time.current
    synced = 0
    missing_ids.each_slice(1000) do |slice|
      rows = slice.map do |contact_id|
        { account_id: account_id, contact_id: contact_id, lead_number: next_number,
          custom_fields_jabvox: {}, created_at: now, updated_at: now }.tap { next_number += 1 }
      end
      result = JabvoxLead.insert_all(rows, unique_by: %i[account_id contact_id]) # rubocop:disable Rails/SkipsModelValidations
      synced += result.rows.size
    end
    synced
  end

  # Flat, string-keyed field map for the WhatsApp template composer: default
  # contact/lead fields under plain keys, custom fields under "custom:<key>".
  # Mirrors Jabvox::BulkWhatsappDispatchService#lead_fields so 1-to-1 and bulk
  # share the same field identifiers. Returns {} when there's no lead.
  def lead_template_fields(lead)
    return {} unless lead

    contact = lead.contact
    fields = {
      'nombre' => contact&.name.to_s,
      'telefono' => contact&.phone_number.to_s,
      'email' => contact&.email.to_s,
      'identificador' => contact&.identifier.to_s,
      'country' => contact&.additional_attributes&.dig('country').to_s,
      'campaign' => lead.jabvox_campaign&.name_jabvox.to_s,
      'afiliado' => lead.jabvox_affiliate&.name.to_s,
      'assignee_name' => lead.assignee&.name.to_s
    }
    (lead.custom_fields_jabvox || {}).each { |k, v| fields["custom:#{k}"] = v.to_s }
    fields
  end

  # [{ key:, label: }] for every custom column of the account's leads table, so
  # the template composer can list all custom fields even when the contact has
  # no value in them. Empty when there's no leads custom table.
  def lead_custom_field_defs
    table = Current.account.jabvox_custom_tables.for_leads.first
    return [] unless table

    table.jabvox_custom_columns.ordered.map do |c|
      { key: c.name_jabvox, label: c.label_jabvox }
    end
  end

  # Enforce a custom-role permission ONLY for users who actually have a custom role.
  # Users on a standard role (custom_role nil) keep the historical flow untouched;
  # admins always pass because jabvox_authorize! bypasses for administrators.
  def jabvox_gate!(key)
    return if Current.account_user&.custom_role.nil?

    jabvox_authorize!(key)
  end

  def update_contact_fields(lead)
    return if params[:contact].blank? || lead.contact.blank?
    # Un payload malformado (contact como string/array) no debe tumbar el update.
    return unless params[:contact].is_a?(ActionController::Parameters)

    attrs = params.require(:contact).permit(:phone_number, :email)
    # country y documento viven en additional_attributes del contacto.
    additional = lead.contact.additional_attributes || {}
    additional_changed = false
    { country: 'country', identification: 'jabvox_identification_number' }.each do |param_key, attr_key|
      next unless params[:contact].key?(param_key)

      additional = additional.merge(attr_key => params.dig(:contact, param_key).to_s.strip)
      additional_changed = true
    end
    lead.contact.additional_attributes = additional if additional_changed
    # Guardar también cuando SOLO cambian los additional_attributes (antes un
    # cambio de país sin tocar teléfono/email se perdía).
    lead.contact.update!(attrs) if attrs.present? || additional_changed
  end

  def update_assignee(lead)
    return unless params.key?(:assignee_id)

    assignee = params[:assignee_id].present? ? Current.account.users.find(params[:assignee_id]) : nil
    lead.update!(assignee: assignee)
    # Follow the lead's new owner on the contact's open conversations (no-op if
    # unassigned — we don't pull conversations away from an agent on unassign).
    Jabvox::LeadConversationAssignmentSync.new(Current.account).sync_lead(lead, assignee)
  end

  def update_campaign(lead)
    return unless params.key?(:campaign_name)

    lead.update!(jabvox_campaign: find_or_create_campaign(params[:campaign_name]))
  end

  def update_custom_fields(lead)
    return if params[:custom_fields].blank?

    result = sanitize_custom_fields(lead)
    raise ActiveRecord::RecordInvalid, invalid_custom_fields_record(lead, result.errors) unless result.valid?

    lead.update!(custom_fields_jabvox: result.data)
  end

  def sanitize_custom_fields(lead)
    Jabvox::LeadCustomFieldsSanitizer.new(
      Current.account, lead.custom_fields_jabvox, params.require(:custom_fields).permit!.to_h
    ).call
  end

  # Wraps sanitizer errors in the RecordInvalid shape update_details already
  # rescues, so they surface as a 422 with the messages joined.
  def invalid_custom_fields_record(lead, errors)
    errors.each { |message| lead.errors.add(:base, message) }
    lead
  end

  def check_leads_enabled
    return if Current.account.jabvox_leads_enabled_jabvox?

    if action_name == 'for_contact'
      render json: { id: nil, campaign_id: nil, campaign_name: nil }
    else
      render json: { error: 'Leads module not enabled' }, status: :forbidden
    end
  end

  # Deleting leads requires BOTH: the per-account "delete leads" module enabled
  # from Super Admin, AND the current user being an administrator. Agents and
  # custom roles can never delete, regardless of any custom-role permission.
  def check_lead_delete_allowed
    unless Current.account.jabvox_lead_delete_enabled_jabvox?
      return render json: { error: 'Lead deletion is not enabled for this account' }, status: :forbidden
    end

    return if Current.account_user&.administrator?

    render json: { error: 'Only administrators can delete leads' }, status: :forbidden
  end

  def find_or_create_campaign(name)
    return nil if name.blank?

    JabvoxCampaign.find_or_create_by!(account: Current.account, name_jabvox: name.strip)
  rescue ActiveRecord::RecordInvalid
    nil
  end

  # Delegates to the shared filter service so the leads list and the bulk-WhatsApp lead picker
  # apply identical filters + per-agent scoping.
  def build_filter_scope
    Jabvox::LeadsFilterService.new(
      account: Current.account, user: current_user,
      is_admin: jabvox_can?('jabvox_leads_view_all'), filters: params
    ).scope
  end

  # Historic gestiones for the current page: ALL managements per lead within the
  # active date range (not just the latest), the per-lead management count, the
  # per-lead call-typification count, and the global total of managements in the
  # filter. Computed with grouped, batched queries (no N+1). Exposed to the view
  # via @managements_by_contact / @typification_counts / @management_totals.
  def load_management_history(leads)
    contact_ids = leads.filter_map(&:contact_id)
    from = safe_date_param(params[:date_from])
    to = safe_date_param(params[:date_to])

    mgmt = Jabvox::LeadManagementsService.new(Current.account, contact_ids, date_from: from, date_to: to)
    @managements_by_contact = mgmt.by_contact
    @management_counts_by_contact = mgmt.counts_by_contact
    @typification_counts = Jabvox::LeadTypificationCountsService.new(Current.account, leads).by_lead

    # Global total of managements across the WHOLE filter (all matching leads, not
    # just this page), shown as the "X gestiones en total" summary.
    @management_total = management_total_for_filter(from, to)
  end

  # Total managements in the active filter, across every matching lead (capped by
  # the matching-ids limit so it never scans an unbounded set).
  def management_total_for_filter(from, to)
    all_contact_ids = build_filter_scope.where.not('jabvox_leads.contact_id' => nil)
                                        .limit(MATCHING_IDS_LIMIT).pluck('jabvox_leads.contact_id')
    return 0 if all_contact_ids.empty?

    Jabvox::LeadManagementsService.new(Current.account, all_contact_ids, date_from: from, date_to: to).total
  end

  # Parse a yyyy-mm-dd param into a Date, or nil (never raises on bad input).
  def safe_date_param(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def load_conversation_data(contact_ids)
    return {} if contact_ids.empty?

    safe_ids = contact_ids.map(&:to_i)
    account_id = Current.account.id.to_i
    latest_convs = fetch_latest_conversations(account_id, safe_ids)
    mgmt_data = fetch_latest_management_by_contact(account_id, safe_ids)

    inbox_ids = latest_convs.filter_map { |r| r['inbox_id']&.to_i }.uniq
    inboxes = inbox_ids.any? ? Inbox.where(id: inbox_ids).index_by(&:id) : {}
    conv_by_contact = latest_convs.index_by { |r| r['contact_id'].to_i }

    safe_ids.each_with_object({}) do |contact_id, h|
      row = conv_by_contact[contact_id] || {}
      mgmt = mgmt_data[contact_id]
      conv_id = row['conversation_id']&.to_i
      conv_display_id = row['conversation_display_id']&.to_i
      inbox_id = row['inbox_id']&.to_i
      h[contact_id] = {
        conversation_id: conv_id,
        conversation_display_id: conv_display_id,
        inbox_id: inbox_id,
        inbox_name: inbox_id&.positive? ? inboxes[inbox_id]&.name : nil,
        last_management_state: mgmt&.fetch('last_management_state', nil),
        last_management_at: mgmt&.fetch('last_management_at', nil),
        last_management_source: mgmt&.fetch('last_management_source', nil)
      }
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  def fetch_latest_conversations(account_id, contact_ids)
    # Expose BOTH ids:
    #  - conversation_id (PK): used as a FK filter by orders/history endpoints.
    #  - conversation_display_id: per-account number the messages API resolves
    #    via find_by!(display_id:). Sending the PK there 404s when id != display_id.
    sql = <<~SQL.squish
      SELECT DISTINCT ON (contact_id) contact_id, id AS conversation_id, display_id AS conversation_display_id, inbox_id
      FROM conversations
      WHERE account_id = #{account_id} AND contact_id IN (#{contact_ids.join(', ')})
      ORDER BY contact_id, created_at DESC
    SQL
    ApplicationRecord.connection.execute(sql).to_a
  end

  def fetch_latest_management_by_contact(account_id, contact_ids)
    sql = <<~SQL.squish
      SELECT DISTINCT ON (c.contact_id) c.contact_id,
        (m.content_attributes #>> '{}')::json->>'jabvox_management_state_name' AS last_management_state,
        (m.content_attributes #>> '{}')::json->>'jabvox_call_source' AS last_management_source,
        m.created_at AS last_management_at
      FROM conversations c
      JOIN messages m ON m.conversation_id = c.id
      WHERE c.account_id = #{account_id}
        AND c.contact_id IN (#{contact_ids.join(', ')})
        AND m.private = true
        AND (m.content_attributes #>> '{}')::json->>'jabvox_management_state_id' IS NOT NULL
        AND (m.content_attributes #>> '{}')::json->>'jabvox_management_state_id' <> ''
      ORDER BY c.contact_id, m.created_at DESC
    SQL
    ApplicationRecord.connection.execute(sql).index_by { |r| r['contact_id'].to_i }
  end

  # rubocop:disable Metrics/AbcSize
  # Only compute the (static) filter options on the first page or when the client
  # explicitly asks for them, to avoid 6 extra queries on every pagination request.
  def include_filter_options?
    page = params[:page].to_i
    page <= 1 || params[:with_filter_options].present?
  end

  def build_filter_options
    {
      management_states: Current.account.jabvox_management_states.active.ordered
                                .map { |s| { id: s.name_jabvox, name: s.name_jabvox, color: s.color_jabvox } },
      campaigns: Current.account.jabvox_campaigns.ordered.map { |c| { id: c.id, name: c.name_jabvox } },
      inboxes: Current.account.inboxes.order(:name).map { |i| { id: i.id, name: i.name } },
      teams: Current.account.teams.order(:name).map { |t| { id: t.id, name: t.name } },
      assignees: Current.account.users.order(:name).map { |a| { id: a.id, name: a.name } },
      affiliates: Current.account.jabvox_affiliates.where(active: true).order(:name).map { |a| { id: a.id, name: a.name } },
      custom_fields: lead_custom_field_filter_defs
    }
  end

  # Definitions of the account's lead custom columns so the list can offer a
  # SELECTABLE filter (one or many values) and a swappable table column per field.
  # Every field becomes a value selector: the options combine the configured
  # options with the distinct values actually present in the account's leads
  # (shared helper, same as the dialer), so text/date/number fields are pickers
  # too — no free-text or date inputs. Filtering runs through
  # Jabvox::LeadCustomFilter (bind-safe).
  def lead_custom_field_filter_defs
    table = Current.account.jabvox_custom_tables.for_leads.first
    return [] unless table

    columns = table.jabvox_custom_columns.ordered
    values_by_key = Jabvox::LeadCustomFilter.distinct_values(
      Current.account, columns.map(&:name_jabvox)
    )
    columns.map do |c|
      configured = Array(c.options_jabvox).map(&:to_s)
      discovered = values_by_key[c.name_jabvox] || []
      {
        key: c.name_jabvox,
        label: c.label_jabvox.presence || c.name_jabvox,
        column_type: c.column_type_jabvox,
        options: (configured + discovered).reject(&:blank?).uniq.sort
      }
    end
  end
  # rubocop:enable Metrics/AbcSize
end
