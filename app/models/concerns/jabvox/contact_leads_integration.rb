module Jabvox::ContactLeadsIntegration
  extend ActiveSupport::Concern

  included do
    after_commit :jabvox_create_lead, on: :create
  end

  private

  def jabvox_create_lead
    return unless account.jabvox_leads_enabled_jabvox?

    JabvoxLead.find_or_create_by!(account: account, contact: self)
    ensure_resolvable_contact!
  rescue StandardError => e
    Rails.logger.error("Failed to create jabvox lead for contact #{id}: #{e.message}")
  end

  def ensure_resolvable_contact!
    return if email.present? || phone_number.present? || identifier.present?

    update_columns(identifier: "jabvox_#{id}") # rubocop:disable Rails/SkipsModelValidations
  end
end
