# frozen_string_literal: true

# Single source of truth for which leads a dialer campaign targets. Used by
# the campaign form preview (count + paginated list) AND by the runtime
# contact picker, so the number the admin sees is exactly what gets dialed.
#
# Accepts a plain filters hash:
#   jabvox_campaign_id, countries: [], management_state_ids: [], affiliate_ids: [],
#   inbox_ids: [], q, email, phone, custom: { field_key => value },
#   excluded_lead_ids: [], require_phone: true/false
#
# Custom-field keys are slug-sanitized before touching the jsonb path so user
# input can never smuggle SQL.
module Jabvox
  class DialerLeadsFilterService
    def initialize(account, filters)
      @account = account
      @filters = (filters || {}).with_indifferent_access
    end

    def scope
      leads = @account.jabvox_leads.joins(:contact)
      leads = leads.where(jabvox_leads: { jabvox_campaign_id: @filters[:jabvox_campaign_id].to_i }) if @filters[:jabvox_campaign_id].present?
      leads = leads.where("contacts.phone_number IS NOT NULL AND contacts.phone_number <> ''") if @filters[:require_phone]
      leads = apply_countries(leads)
      leads = apply_management_states(leads)
      leads = apply_affiliates(leads)
      leads = apply_inboxes(leads)
      leads = apply_lead_fields(leads)
      leads = apply_custom_fields(leads)
      apply_exclusions(leads)
    end

    # Convenience builder: the stored campaign columns -> filters hash, so the
    # picker and the live counts read the same definition.
    def self.for_campaign(account, campaign, require_phone: false)
      new(account, {
        jabvox_campaign_id: campaign.jabvox_campaign_id,
        countries: campaign.countries_jabvox || [],
        management_state_ids: (campaign.management_state_ids_jabvox || []).map(&:to_s),
        affiliate_ids: campaign.affiliate_ids_jabvox || [],
        inbox_ids: campaign.inbox_ids_jabvox || [],
        excluded_lead_ids: campaign.excluded_lead_ids_jabvox || [],
        require_phone: require_phone
      }.merge((campaign.lead_filters_jabvox || {}).slice('q', 'email', 'phone', 'custom')))
    end

    private

    def apply_countries(leads)
      countries = Array(@filters[:countries]).compact.reject(&:blank?)
      return leads if countries.empty?

      conds = countries.map { "contacts.additional_attributes->>'country' ILIKE ?" }.join(' OR ')
      leads.where(conds, *countries)
    end

    def apply_affiliates(leads)
      affiliate_ids = Array(@filters[:affiliate_ids]).map(&:to_i).select(&:positive?)
      affiliate_ids.any? ? leads.where(jabvox_affiliate_id: affiliate_ids) : leads
    end

    def apply_inboxes(leads)
      inbox_ids = Array(@filters[:inbox_ids]).map(&:to_i).select(&:positive?)
      return leads if inbox_ids.empty?

      leads.where(contact_id: @account.conversations.where(inbox_id: inbox_ids).select(:contact_id))
    end

    def apply_lead_fields(leads)
      leads = leads.where('contacts.name ILIKE ?', "%#{like(@filters[:q])}%") if @filters[:q].present?
      leads = leads.where('contacts.email ILIKE ?', "%#{like(@filters[:email])}%") if @filters[:email].present?
      leads = leads.where('contacts.phone_number ILIKE ?', "%#{like(@filters[:phone])}%") if @filters[:phone].present?
      leads
    end

    # Escapes LIKE wildcards so % / _ in user input match literally.
    def like(value)
      ActiveRecord::Base.sanitize_sql_like(value.to_s)
    end

    # Delegates to the shared Jabvox::LeadCustomFilter so "one or several values"
    # (incl. axios index-hash payloads) and SQL safety match the leads/bulk path.
    def apply_custom_fields(leads)
      Jabvox::LeadCustomFilter.apply(leads, @filters[:custom])
    end

    def apply_exclusions(leads)
      excluded = Array(@filters[:excluded_lead_ids]).map(&:to_i).select(&:positive?)
      excluded.any? ? leads.where.not(jabvox_leads: { id: excluded }) : leads
    end

    def apply_management_states(leads) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      state_ids = Array(@filters[:management_state_ids]).map(&:to_s).reject(&:blank?)
      return leads if state_ids.empty?

      include_none = state_ids.include?('none')
      numeric_ids = state_ids.reject { |id| id == 'none' }.map(&:to_i).select(&:positive?)
      state_names = numeric_ids.any? ? @account.jabvox_management_states.where(id: numeric_ids).pluck(:name_jabvox) : []
      return leads if state_names.empty? && !include_none

      msgs_base = @account.messages.where(private: true)
                          .where("(content_attributes #>> '{}')::json->>'jabvox_management_state_name' IS NOT NULL")
                          .where("(content_attributes #>> '{}')::json->>'jabvox_management_state_name' <> ''")
      contact_ids_with_any_state = @account.conversations
                                           .where(id: msgs_base.select(:conversation_id))
                                           .select(:contact_id)

      if state_names.any?
        # Per contact, find the latest (highest ID) management-state message so
        # we match the LAST gestión, not any historical one.
        latest_per_contact = msgs_base
                             .joins('INNER JOIN conversations ON conversations.id = messages.conversation_id')
                             .unscope(:order)
                             .group('conversations.contact_id')
                             .select('conversations.contact_id, MAX(messages.id) AS max_id')
        name_conds = state_names.map { "((content_attributes #>> '{}')::json->>'jabvox_management_state_name' = ?)" }.join(' OR ')
        contact_ids_matching = @account.messages
                                       .joins("INNER JOIN (#{latest_per_contact.to_sql}) lpc ON messages.id = lpc.max_id")
                                       .joins('INNER JOIN conversations ON conversations.id = messages.conversation_id')
                                       .where(name_conds, *state_names)
                                       .select('conversations.contact_id')
        if include_none
          leads.where("jabvox_leads.contact_id IN (#{contact_ids_matching.to_sql}) OR " \
                      "jabvox_leads.contact_id NOT IN (#{contact_ids_with_any_state.to_sql})")
        else
          leads.where(contact_id: contact_ids_matching)
        end
      else
        leads.where("jabvox_leads.contact_id NOT IN (#{contact_ids_with_any_state.to_sql})")
      end
    end
  end
end
