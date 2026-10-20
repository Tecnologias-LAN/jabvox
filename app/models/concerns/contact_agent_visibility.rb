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
      # Agentes con el permiso "ver todos los contactos" (rol personalizado) ven
      # todos, coherente con jabvox/contacts_list_controller y el envio masivo.
      return all if JabvoxPermissions.user_grants_permission?(account_user, 'jabvox_contacts_view_all')

      user_id = account_user.user_id
      conversation_contact_ids = Conversation.where(account_id: account_user.account_id, assignee_id: user_id)
                                             .select(:contact_id)

      # Dos vías: el contacto le está asignado directamente, o lo está una de sus
      # conversaciones. Antes la primera vía miraba el responsable del lead; al retirar
      # Leads ese dato vive en el propio contacto.
      where(id: conversation_contact_ids).or(where(assignee_id: user_id))
    end
  end
end
