# Keeps the contact's lead in sync when a conversation is assigned to an agent:
# the lead must exist and be assigned to the SAME agent, so the agent sees the
# contact in Leads and Kanban (both are filtered by the lead's assignee, not the
# conversation's). Covers every assignment path — manual, API, bulk actions and
# auto-assignment — because it hooks the model itself.
module Jabvox::ConversationLeadAssignment
  extend ActiveSupport::Concern

  included do
    after_commit :jabvox_sync_lead_assignee
  end

  private

  def jabvox_sync_lead_assignee
    return unless saved_change_to_assignee_id?
    return if assignee_id.blank? || contact.blank?

    lead = JabvoxLead.find_by(account: account, contact: contact)
    # Create the lead on the spot only when the leads module is active
    # (same gate as Jabvox::ContactLeadsIntegration).
    lead ||= JabvoxLead.create!(account: account, contact: contact) if account.jabvox_leads_enabled_jabvox?
    return if lead.nil? || lead.assignee_id == assignee_id

    lead.update!(assignee_id: assignee_id)
  rescue StandardError => e
    # Never break the assignment flow itself; log and move on.
    Rails.logger.error("[Jabvox] lead assignee sync failed for conversation #{id}: #{e.message}")
  end
end
