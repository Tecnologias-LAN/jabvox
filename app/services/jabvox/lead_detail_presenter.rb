# frozen_string_literal: true

module Jabvox
  # Builds the full "lead detail" payload for one contact, mirroring the lead
  # detail page (JabvoxLeadDetail.vue): contact fields, document/type/country/
  # bio from additional_attributes, campaign, affiliate, lead assignee, the
  # inbox of the contact's latest conversation, and the custom lead fields
  # (label + type + value) from the for_leads custom table.
  #
  # Used by the conversation sidebar's "Información del lead" panel.
  class LeadDetailPresenter
      def initialize(account:, contact_id:)
        @account = account
        @contact_id = contact_id.to_i
      end

      def call
        contact = @account.contacts.find_by(id: @contact_id)
        return nil unless contact

        lead = JabvoxLead.where(account_id: @account.id, contact_id: @contact_id)
                         .includes(:jabvox_campaign, :jabvox_affiliate, :assignee).first
        add = contact.additional_attributes || {}

        {
          contact: contact_view(contact, add),
          lead: lead ? lead_view(lead) : nil,
          inbox_name: latest_inbox_name(contact),
          custom_fields: custom_fields(lead)
        }
      end

      private

      def contact_view(contact, add)
        {
          id: contact.id,
          name: contact.name,
          email: contact.email,
          phone: contact.phone_number,
          avatar_url: contact.avatar_url,
          identification: add['jabvox_identification_number'],
          contact_type: add['jabvox_contact_type'].presence || 'persona',
          country: add['country'],
          city: add['city'],
          company_name: add['company_name'],
          bio: add['description']
        }
      end

      def lead_view(lead)
        {
          id: lead.id,
          lead_number: lead.lead_number,
          created_at: lead.created_at,
          is_sold: lead.is_sold_jabvox,
          campaign_name: lead.jabvox_campaign&.name_jabvox,
          affiliate_name: lead.jabvox_affiliate&.name,
          assignee_name: lead.assignee&.name
        }
      end

      # Inbox of the contact's most recent conversation (same rule as the lead
      # detail page).
      def latest_inbox_name(contact)
        conv = @account.conversations.where(contact_id: contact.id)
                       .order(created_at: :desc).select(:inbox_id).first
        conv&.inbox&.name
      end

      # Custom lead fields: cross the for_leads column definitions (label, type,
      # options) with the values stored inline on the lead.
      def custom_fields(lead)
        table = @account.jabvox_custom_tables.for_leads.first
        return [] unless table

        values = lead&.custom_fields_jabvox || {}
        table.jabvox_custom_columns.order(:position_jabvox).map do |col|
          { label: col.label_jabvox, type: col.column_type_jabvox,
            value: display_value(col, values[col.name_jabvox]) }
        end
      end

      # Human-readable value per column type (mirrors the detail page render).
      def display_value(col, raw)
        return nil if raw.nil? || raw == ''

        case col.column_type_jabvox
        when 'boolean' then raw ? 'Sí' : 'No'
        when 'multiselect' then Array(raw).join(', ')
        else raw.to_s
        end
      end
  end
end
