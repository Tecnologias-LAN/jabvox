# Keeps the contact's lead in sync when a conversation's assignee changes: the
# lead must have the SAME agent as the conversation (the conversation is the
# source of truth), so the agent sees the contact in Leads and Kanban (both are
# filtered by the lead's assignee, not the conversation's). Mirrors both ways:
# assigning the conversation assigns the lead, and UNASSIGNING the conversation
# unassigns the lead too. Covers every assignment path — manual, API, bulk and
# auto-assignment — because it hooks the model itself.
module Jabvox::ConversationLeadAssignment
  extend ActiveSupport::Concern

  included do
    after_commit :jabvox_sync_lead_assignee
  end

  private

  def jabvox_sync_lead_assignee
    return unless saved_change_to_assignee_id?
    return if contact.blank?

    lead = jabvox_lead_for_sync
    return if lead.nil? || lead.assignee_id == assignee_id

    # assignee_id may be nil here (conversation unassigned) → mirror it to the lead.
    lead.update!(assignee_id: assignee_id)
  rescue StandardError => e
    # Never break the assignment flow itself; log and move on.
    Rails.logger.error("[Jabvox] lead assignee sync failed for conversation #{id}: #{e.message}")
  end

  # Existing lead of the contact, or a fresh one only when ASSIGNING and the leads
  # module is active. On unassign we never create a lead just to leave it empty.
  def jabvox_lead_for_sync
    lead = JabvoxLead.find_by(account: account, contact: contact)
    return lead if lead
    return nil unless assignee_id.present? && account.jabvox_leads_enabled_jabvox?

    JabvoxLead.create!(account: account, contact: contact)
  end
end
