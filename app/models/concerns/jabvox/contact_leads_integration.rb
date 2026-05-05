module Jabvox::ContactLeadsIntegration
  extend ActiveSupport::Concern

  included do
    after_commit :jabvox_create_lead, on: :create
  end

  private

  def jabvox_create_lead
    return unless account.jabvox_leads_enabled_jabvox?

    JabvoxLead.find_or_create_by!(account: account, contact: self)
  rescue StandardError => e
    Rails.logger.error("Failed to create jabvox lead for contact #{id}: #{e.message}")
  end
end
