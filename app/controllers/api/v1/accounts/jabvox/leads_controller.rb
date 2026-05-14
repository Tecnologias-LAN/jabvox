class Api::V1::Accounts::Jabvox::LeadsController < Api::V1::Accounts::BaseController
  before_action :check_leads_enabled

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

    lead_ids = leads.pluck(:id)
    JabvoxKanbanConversationStage.where(jabvox_lead_id: lead_ids).delete_all
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

  private

  def check_leads_enabled
    render json: { error: 'Leads module not enabled' }, status: :forbidden unless Current.account.jabvox_leads_enabled_jabvox?
  end

  def find_or_create_campaign(name)
    return nil if name.blank?

    JabvoxCampaign.find_or_create_by!(account: Current.account, name_jabvox: name.strip)
  rescue ActiveRecord::RecordInvalid
    nil
  end

  # rubocop:disable Metrics/AbcSize
  def build_filter_scope
    leads = Current.account.jabvox_leads.joins(:contact)
    leads = leads.where(assignee_id: current_user.id) unless Current.account_user.administrator?
    leads = leads.where(jabvox_leads: { id: params[:lead_id].to_i }) if params[:lead_id].present?
    leads = leads.where('contacts.name ILIKE ?', "%#{params[:q]}%") if params[:q].present?
    leads = leads.where('contacts.email ILIKE ?', "%#{params[:email]}%") if params[:email].present?
    leads = leads.where('contacts.phone_number ILIKE ?', "%#{params[:phone]}%") if params[:phone].present?
    leads = leads.where("contacts.additional_attributes->>'country' ILIKE ?", "%#{params[:country]}%") if params[:country].present?
    leads = leads.where(jabvox_campaign_id: params[:campaign_id]) if params[:campaign_id].present?
    if params[:sold].present?
      order_contact_ids = Current.account.jabvox_orders.where.not(contact_id: nil)
      order_contact_ids = order_contact_ids.where(doc_type: 'QUOTE') if params[:sold] == 'quotes'
      order_contact_ids = order_contact_ids.where(doc_type: 'SALE') if params[:sold] == 'sales'
      leads = leads.where(jabvox_leads: { contact_id: order_contact_ids.select(:contact_id) })
    end
    leads = leads.where(jabvox_affiliate_id: nil) if params[:affiliate_id] == 'own'
    leads = leads.where(jabvox_affiliate_id: params[:affiliate_id]) if params[:affiliate_id].present? && params[:affiliate_id] != 'own'
    leads = apply_conversation_filters(leads)
    leads = apply_management_filters(leads)
    sort_col = SORTABLE_COLUMNS[params[:sort_column]] || 'jabvox_leads.created_at'
    sort_dir = params[:sort_direction] == 'asc' ? 'ASC' : 'DESC'
    leads.order(Arel.sql("#{sort_col} #{sort_dir}"))
  end
  # rubocop:enable Metrics/AbcSize

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def apply_conversation_filters(leads)
    return leads unless params[:inbox_id].present? || params[:assignee_id].present? ||
                        params[:team_id].present? || params[:status].present?

    conv_q = Current.account.conversations
    conv_q = conv_q.where(inbox_id: params[:inbox_id]) if params[:inbox_id].present?
    conv_q = conv_q.where(assignee_id: params[:assignee_id]) if params[:assignee_id].present?
    conv_q = conv_q.where(team_id: params[:team_id]) if params[:team_id].present?
    conv_q = conv_q.where(status: params[:status]) if params[:status].present?
    leads.where(contact_id: conv_q.select(:contact_id))
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # rubocop:disable Metrics/AbcSize
  def apply_management_filters(leads)
    return leads unless params[:management_state].present? || params[:date_from].present? || params[:date_to].present?

    msg_q = Current.account.messages.where(private: true)
                   .where("(content_attributes #>> '{}')::json->>'jabvox_management_state_name' IS NOT NULL")
                   .where("(content_attributes #>> '{}')::json->>'jabvox_management_state_name' <> ''")
    if params[:management_state].present?
      msg_q = msg_q.where("(content_attributes #>> '{}')::json->>'jabvox_management_state_name' = ?",
                          params[:management_state])
    end
    msg_q = msg_q.where('messages.created_at >= ?', Date.parse(params[:date_from]).beginning_of_day) if params[:date_from].present?
    msg_q = msg_q.where('messages.created_at <= ?', Date.parse(params[:date_to]).end_of_day) if params[:date_to].present?
    leads.where(contact_id: Current.account.conversations.where(id: msg_q.select(:conversation_id)).select(:contact_id))
  end
  # rubocop:enable Metrics/AbcSize

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
      inbox_id = row['inbox_id']&.to_i
      h[contact_id] = {
        conversation_id: conv_id,
        inbox_id: inbox_id,
        inbox_name: inbox_id&.positive? ? inboxes[inbox_id]&.name : nil,
        last_management_state: mgmt&.fetch('last_management_state', nil),
        last_management_at: mgmt&.fetch('last_management_at', nil)
      }
    end
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  def fetch_latest_conversations(account_id, contact_ids)
    sql = <<~SQL.squish
      SELECT DISTINCT ON (contact_id) contact_id, id AS conversation_id, inbox_id
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
