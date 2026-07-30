# Jabvox extension for DataImportJob: after core contact import, create a
# JabvoxLead (and its campaign) per imported contact. Kept out of the core job
# so the upstream import logic stays untouched.
module Jabvox::DataImportLeads
  def create_jabvox_leads(contacts, campaign_names)
    contacts.each_with_index do |item, idx|
      # After upstream's label refactor, entries are { contact:, labels: } hashes.
      contact = item.is_a?(Hash) ? item[:contact] : item
      next if contact.nil? || contact.id.blank?

      campaign_name = campaign_names[idx]
      campaign = JabvoxCampaign.find_or_create_by!(account: @data_import.account, name_jabvox: campaign_name) if campaign_name.present?
      JabvoxLead.find_or_create_by!(account: @data_import.account, contact: contact) do |lead|
        lead.jabvox_campaign = campaign
      end
    end
  rescue StandardError => e
    Rails.logger.error("Jabvox leads creation failed: #{e.message}")
  end
end
