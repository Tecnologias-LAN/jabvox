class Api::V1::Accounts::Jabvox::LeadsController < Api::V1::Accounts::BaseController
  include JabvoxPermissions

  before_action :check_leads_enabled
  # Custom-role gates: only enforced when the user has a custom role assigned, so plain
  # agents/admins keep their historical behavior (admins always pass via jabvox_gate!).
  before_action -> { jabvox_gate!('jabvox_leads_assign') }, only: %i[bulk_assign bulk_unassign]
  before_action -> { jabvox_gate!('jabvox_leads_delete') }, only: :bulk_destroy
  before_action -> { jabvox_gate!('jabvox_leads_edit') }, only: :update_details

  PER_PAGE_OPTIONS = [10, 25, 50, 100, 200].freeze
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
    @filter_options = build_filter_options
  end

  def show
    @lead = Current.account.jabvox_leads.includes(:contact, :jabvox_campaign, :assignee, :jabvox_affiliate).find(params[:id])
    @conv_data = (load_conversation_data([@lead.contact_id]))[@lead.contact_id] || {}
  end

  def for_contact
    lead = Current.account.jabvox_leads.includes(:jabvox_campaign).find_by(contact_id: params[:contact_id])
    render json: {
      id: lead&.id,
      campaign_id: lead&.jabvox_campaign_id,
      campaign_name: lead&.jabvox_campaign&.name_jabvox
    }
  end

  def update_contact_lead
    lead = JabvoxLead.find_or_initialize_by(account: Current.account, contact_id: params[:contact_id].to_i)
    lead.jabvox_campaign = find_or_create_campaign(params[:campaign_name])
    lead.save!
    render json: { id: lead.id, campaign_id: lead.jabvox_campaign_id, campaign_name: lead.jabvox_campaign&.name_jabvox }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def sync_contacts
    count = 0
    Current.account.contacts.find_each do |contact|
      JabvoxLead.find_or_create_by!(account: Current.account, contact: contact)
      count += 1
    rescue StandardError
      next
    end
    render json: { synced: count }
  end

  def bulk_assign
    assignee = Current.account.users.find(params[:assignee_id])
    leads = Current.account.jabvox_leads.where(id: params[:lead_ids])
    count = leads.count
    leads.update_all(assignee_id: assignee.id)
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

  private

  # Enforce a custom-role permission ONLY for users who actually have a custom role.
  # Users on a standard role (custom_role nil) keep the historical flow untouched;
  # admins always pass because jabvox_authorize! bypasses for administrators.
  def jabvox_gate!(key)
    jabvox_authorize!(key)
  end

  def update_contact_fields(lead)
    return if params[:contact].blank? || lead.contact.blank?

    attrs = params.require(:contact).permit(:phone_number, :email)
    country = params.dig(:contact, :country)
    if country.present? || params[:contact].key?(:country)
      additional = lead.contact.additional_attributes || {}
      lead.contact.additional_attributes = additional.merge('country' => country)
    end
    lead.contact.update!(attrs) if attrs.present?
  end

  def update_assignee(lead)
    return unless params.key?(:assignee_id)

    assignee = params[:assignee_id].present? ? Current.account.users.find(params[:assignee_id]) : nil
    lead.update!(assignee: assignee)
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
        last_management_at: mgmt&.fetch('last_management_at', nil)
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
        m.created_at AS last_management_at
      FROM conversations c
      JOIN messages m ON m.conversation_id = c.id
      WHERE c.account_id = #{account_id}
        AND c.contact_id IN (#{contact_ids.join(', ')})
        AND m.private = true
        AND (m.content_attributes #>> '{}')::json->>'jabvox_management_state_name' IS NOT NULL
        AND (m.content_attributes #>> '{}')::json->>'jabvox_management_state_name' <> ''
      ORDER BY c.contact_id, m.created_at DESC
    SQL
    ApplicationRecord.connection.execute(sql).index_by { |r| r['contact_id'].to_i }
  end

  # rubocop:disable Metrics/AbcSize
  def build_filter_options
    {
      management_states: Current.account.jabvox_management_states.active.ordered
                                .map { |s| { id: s.name_jabvox, name: s.name_jabvox, color: s.color_jabvox } },
      campaigns: Current.account.jabvox_campaigns.ordered.map { |c| { id: c.id, name: c.name_jabvox } },
      inboxes: Current.account.inboxes.order(:name).map { |i| { id: i.id, name: i.name } },
      teams: Current.account.teams.order(:name).map { |t| { id: t.id, name: t.name } },
      assignees: Current.account.users.order(:name).map { |a| { id: a.id, name: a.name } },
      affiliates: Current.account.jabvox_affiliates.where(active: true).order(:name).map { |a| { id: a.id, name: a.name } }
    }
  end
  # rubocop:enable Metrics/AbcSize
end
