# Scopes that decide which contacts get listed.
#
# - `resolved_contacts` keeps only contacts with identifying info (or leads under
#   CRM v2) — the base of every contacts list.
# - `visible_to` restricts that list by role: admins get every contact; a plain
#   agent only sees contacts they are connected to through either a conversation
#   assigned to them OR a Jabvox lead assigned to them. Both underlying columns
#   (conversations.assignee_id, jabvox_leads.assignee_id) are indexed, so the two
#   id sub-selects stay cheap. `account_user` may be nil (internal callers) — in
#   that case we do NOT restrict, matching the historical "show everything"
#   behavior.
module ContactAgentVisibility
  extend ActiveSupport::Concern

  class_methods do
    def resolved_contacts(use_crm_v2: false)
      return where(contact_type: 'lead') if use_crm_v2

      where("contacts.email <> '' OR contacts.phone_number <> '' OR contacts.identifier <> ''")
    end

    def visible_to(account_user)
      return all if account_user.nil? || account_user.administrator?

      user_id = account_user.user_id
      conversation_contact_ids = Conversation.where(account_id: account_user.account_id, assignee_id: user_id)
                                             .select(:contact_id)
      lead_contact_ids = JabvoxLead.where(account_id: account_user.account_id, assignee_id: user_id)
                                   .select(:contact_id)

      where(id: conversation_contact_ids).or(where(id: lead_contact_ids))
    end
  end
end
