# Keeps a contact's conversations assigned to the same agent that owns the lead.
#
# When a Jabvox lead is assigned to an agent (manually from the Leads screen, in
# bulk, or automatically by the dialer after a call connects), the contact's
# conversations must follow: the agent who owns the lead should also own the
# conversation. Without this, a lead could be assigned to agent A while its
# conversation stays unassigned or with a different agent — the inconsistency
# the stress test surfaced.
#
# Scope of what gets reassigned:
#   - Only OPEN conversations of the lead's contact (resolved/snoozed history is
#     left untouched — we don't rewrite closed work).
#   - Only when the current assignee differs from the target agent (no-op writes
#     are skipped, so no spurious events/notifications fire).
#
# Assignment goes through Conversations::AssignmentService so the normal side
# effects (assignment notification, reporting event, participants) all run,
# exactly as a manual assignment in the UI would.
module Jabvox
  class LeadConversationAssignmentSync
    def initialize(account)
      @account = account
    end

    # Sync a single lead to a user. Passing nil UNASSIGNS the contact's open
    # conversations too (the lead and its conversations must stay in sync in both
    # directions: assigning follows the new owner, unassigning clears them).
    def sync_lead(lead, user)
      return 0 if lead.nil? || lead.contact_id.blank?

      reassign_open_conversations(lead.contact_id, user&.id)
    end

    # Sync many leads to the same user in one pass. Returns the number of
    # conversations actually reassigned.
    def sync_leads(leads, user)
      return 0 if user.nil?

      contact_ids = Array(leads).map { |l| l.respond_to?(:contact_id) ? l.contact_id : l }.compact.uniq
      contact_ids.sum { |cid| reassign_open_conversations(cid, user.id) }
    end

    private

    def reassign_open_conversations(contact_id, user_id)
      count = 0
      # `IS DISTINCT FROM` compara correctamente incluso con NULL (a diferencia de
      # `<>`, que da NULL frente a NULL). Así funciona en ambos sentidos:
      #   - asignar a un agente: recoge las que estén sin asignar o con otro agente;
      #   - desasignar (user_id nil): recoge las que TENGAN algún agente, para limpiarlas.
      @account.conversations
              .where(contact_id: contact_id, status: :open)
              .where('assignee_id IS DISTINCT FROM ?', user_id)
              .find_each do |conversation|
        Conversations::AssignmentService.new(conversation: conversation, assignee_id: user_id).perform
        count += 1
      rescue StandardError => e
        Rails.logger.error(
          "[LeadConversationAssignmentSync] failed | conversation=#{conversation.id} " \
          "user=#{user_id} #{e.class}: #{e.message}"
        )
      end
      count
    end
  end
end
