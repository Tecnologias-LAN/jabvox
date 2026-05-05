# frozen_string_literal: true

module Jabvox
  class DialerContactPickerService # rubocop:disable Metrics/ClassLength
    def initialize(account, campaign)
      @account = account
      @campaign = campaign
    end

    def pick
      filter_leads.includes(:contact).order('RANDOM()').first
    end

    private

    def filter_leads # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      leads = @account.jabvox_leads.joins(:contact)
      leads = leads.where(jabvox_leads: { jabvox_campaign_id: @campaign.jabvox_campaign_id.to_i }) if @campaign.jabvox_campaign_id.present?
      leads = leads.where("contacts.phone_number IS NOT NULL AND contacts.phone_number <> ''")
      leads = filter_by_countries(leads)

      state_ids = (@campaign.management_state_ids_jabvox || []).map(&:to_s).reject(&:blank?)
      leads = filter_by_management_states(leads, state_ids) if state_ids.any?

      affiliate_ids = (@campaign.affiliate_ids_jabvox || []).map(&:to_i).select(&:positive?)
      leads = leads.where(jabvox_affiliate_id: affiliate_ids) if affiliate_ids.any?

      inbox_ids = (@campaign.inbox_ids_jabvox || []).map(&:to_i).select(&:positive?)
      if inbox_ids.any?
        contact_ids_in_inboxes = @account.conversations.where(inbox_id: inbox_ids).select(:contact_id)
        leads = leads.where(contact_id: contact_ids_in_inboxes)
      end

      leads
    end

    def filter_by_countries(leads)
      countries = (@campaign.countries_jabvox || []).compact.reject(&:blank?)
      return leads unless countries.any?

      conds = countries.map { "contacts.additional_attributes->>'country' ILIKE ?" }.join(' OR ')
      leads.where(conds, *countries)
    end

    def filter_by_management_states(leads, state_ids) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
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
      elsif include_none
        leads.where("jabvox_leads.contact_id NOT IN (#{contact_ids_with_any_state.to_sql})")
      else
        leads
      end
    end
  end
end
