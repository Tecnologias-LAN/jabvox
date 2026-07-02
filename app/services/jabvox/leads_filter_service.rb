# Builds the filtered, sorted JabvoxLead scope shared by the leads list and the bulk-WhatsApp
# lead picker, so both apply exactly the same filters and per-agent scoping. `filters` is the
# same param hash the leads index accepts (q, email, phone, country, campaign_id, sold,
# affiliate_id, inbox_id, assignee_id, team_id, status, management_state, date_from/to, sort).
class Jabvox::LeadsFilterService
  SORTABLE_COLUMNS = {
    'created_at' => 'jabvox_leads.created_at',
    'name' => 'contacts.name',
    'lead_number' => 'jabvox_leads.lead_number'
  }.freeze

  def initialize(account:, user:, is_admin:, filters: {})
    @account = account
    @user = user
    @is_admin = is_admin
    # `filters` may be a plain Hash (bulk-WhatsApp lead picker) or
    # ActionController::Parameters (leads index). Normalize both to an
    # indifferent-access hash; ActionController::Parameters needs to_unsafe_h
    # first since it doesn't respond to with_indifferent_access.
    raw = filters || {}
    raw = raw.to_unsafe_h if raw.respond_to?(:to_unsafe_h)
    @filters = raw.with_indifferent_access
  end

  # rubocop:disable Metrics/AbcSize
  def scope
    leads = @account.jabvox_leads.joins(:contact)
    # `@is_admin` is really "may view all leads" (admin OR the jabvox_leads_view_all custom-role
    # grant). Everyone else only ever sees their own leads — same rule as the leads list and kanban.
    leads = leads.where(assignee_id: @user.id) unless @is_admin
    leads = leads.where(jabvox_leads: { id: @filters[:lead_id].to_i }) if @filters[:lead_id].present?
    leads = leads.where('contacts.name ILIKE ?', "%#{@filters[:q]}%") if @filters[:q].present?
    leads = leads.where('contacts.email ILIKE ?', "%#{@filters[:email]}%") if @filters[:email].present?
    leads = leads.where('contacts.phone_number ILIKE ?', "%#{@filters[:phone]}%") if @filters[:phone].present?
    leads = leads.where("contacts.additional_attributes->>'country' ILIKE ?", "%#{@filters[:country]}%") if @filters[:country].present?
    leads = leads.where(jabvox_campaign_id: @filters[:campaign_id]) if @filters[:campaign_id].present?
    leads = apply_sold_filter(leads)
    leads = apply_affiliate_filter(leads)
    leads = apply_conversation_filters(leads)
    leads = apply_management_filters(leads)
    leads = apply_custom_field_filters(leads)
    leads.order(order_clause)
  end
  # rubocop:enable Metrics/AbcSize

  private

  # Filter by lead custom fields stored in custom_fields_jabvox (jsonb key => value). `custom`
  # is a hash of { field_key => value }; each is matched case-insensitively as a substring.
  # Keys are sanitized to the same slug format used when custom columns are created, so an
  # attacker can't smuggle SQL through the jsonb path.
  def apply_custom_field_filters(leads)
    custom = @filters[:custom]
    return leads unless custom.respond_to?(:each_pair)

    custom.each_pair do |raw_key, value|
      next if value.to_s.strip.blank?

      key = raw_key.to_s.downcase.gsub(/[^a-z0-9_]/, '')
      next if key.blank?

      leads = leads.where('jabvox_leads.custom_fields_jabvox ->> ? ILIKE ?', key, "%#{value}%")
    end
    leads
  end

  def apply_sold_filter(leads)
    return leads if @filters[:sold].blank?

    order_contact_ids = @account.jabvox_orders.where.not(contact_id: nil)
    order_contact_ids = order_contact_ids.where(doc_type: 'QUOTE') if @filters[:sold] == 'quotes'
    order_contact_ids = order_contact_ids.where(doc_type: 'SALE') if @filters[:sold] == 'sales'
    leads.where(jabvox_leads: { contact_id: order_contact_ids.select(:contact_id) })
  end

  def apply_affiliate_filter(leads)
    return leads.where(jabvox_affiliate_id: nil) if @filters[:affiliate_id] == 'own'
    return leads if @filters[:affiliate_id].blank?

    leads.where(jabvox_affiliate_id: @filters[:affiliate_id])
  end

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def apply_conversation_filters(leads)
    return leads unless @filters[:inbox_id].present? || @filters[:assignee_id].present? ||
                        @filters[:team_id].present? || @filters[:status].present?

    conv_q = @account.conversations
    conv_q = conv_q.where(inbox_id: @filters[:inbox_id]) if @filters[:inbox_id].present?
    conv_q = conv_q.where(assignee_id: @filters[:assignee_id]) if @filters[:assignee_id].present?
    conv_q = conv_q.where(team_id: @filters[:team_id]) if @filters[:team_id].present?
    conv_q = conv_q.where(status: @filters[:status]) if @filters[:status].present?
    leads.where(contact_id: conv_q.select(:contact_id))
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # rubocop:disable Metrics/AbcSize
  def apply_management_filters(leads)
    return leads unless @filters[:management_state].present? || @filters[:date_from].present? || @filters[:date_to].present?

    msg_q = @account.messages.where(private: true)
                    .where("(content_attributes #>> '{}')::json->>'jabvox_management_state_name' IS NOT NULL")
                    .where("(content_attributes #>> '{}')::json->>'jabvox_management_state_name' <> ''")
    if @filters[:management_state].present?
      msg_q = msg_q.where("(content_attributes #>> '{}')::json->>'jabvox_management_state_name' = ?", @filters[:management_state])
    end
    msg_q = msg_q.where('messages.created_at >= ?', Date.parse(@filters[:date_from]).beginning_of_day) if @filters[:date_from].present?
    msg_q = msg_q.where('messages.created_at <= ?', Date.parse(@filters[:date_to]).end_of_day) if @filters[:date_to].present?
    leads.where(contact_id: @account.conversations.where(id: msg_q.select(:conversation_id)).select(:contact_id))
  end
  # rubocop:enable Metrics/AbcSize

  def order_clause
    sort_col = SORTABLE_COLUMNS[@filters[:sort_column]] || 'jabvox_leads.created_at'
    sort_dir = @filters[:sort_direction] == 'asc' ? 'ASC' : 'DESC'
    Arel.sql("#{sort_col} #{sort_dir}")
  end
end
