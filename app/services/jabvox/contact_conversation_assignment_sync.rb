# Mantiene las conversaciones de un contacto asignadas al mismo agente que lo tiene a él.
#
# Cuando un contacto se asigna a un agente (manualmente, en lote, o automáticamente por el
# marcador al conectar una llamada), sus conversaciones deben seguirlo: quien es responsable
# del contacto debe serlo también de la conversación. Sin esto, un contacto podría quedar
# asignado al agente A mientras su conversación sigue sin asignar o con otro agente.
#
# Qué se reasigna:
#   - TODAS las conversaciones del contacto, sea cual sea su estado: al filtrar "mías" se
#     espera encontrar también las resueltas. Cada reasignación deja su entrada en el
#     historial de la conversación.
#   - Only when the current assignee differs from the target agent (no-op writes
#     are skipped, so no spurious events/notifications fire).
#
# Assignment goes through Conversations::AssignmentService so the normal side
# effects (assignment notification, reporting event, participants) all run,
# exactly as a manual assignment in the UI would.
class Jabvox::ContactConversationAssignmentSync
  def initialize(account)
    @account = account
  end

  # Sincroniza UN contacto con un usuario. Pasar nil DESASIGNA también sus conversaciones
  # abiertas: contacto y conversaciones deben seguirse en ambos sentidos.
  def sync_contact(contact, user)
    contact_id = contact.respond_to?(:id) ? contact.id : contact
    return 0 if contact_id.blank?

    reassign_conversations(contact_id, user&.id)
  end

  # Sincroniza varios contactos con el mismo usuario en una pasada. Devuelve cuántas
  # conversaciones se reasignaron. Acepta registros o ids sueltos.
  def sync_contacts(contacts, user)
    return 0 if user.nil?

    contact_ids = Array(contacts).filter_map { |c| c.respond_to?(:id) ? c.id : c }.uniq
    contact_ids.sum { |cid| reassign_conversations(cid, user.id) }
  end

  private

  def reassign_conversations(contact_id, user_id)
    count = 0
    # `IS DISTINCT FROM` compara correctamente incluso con NULL (a diferencia de
    # `<>`, que da NULL frente a NULL). Así funciona en ambos sentidos:
    #   - asignar a un agente: recoge las que estén sin asignar o con otro agente;
    #   - desasignar (user_id nil): recoge las que TENGAN algún agente, para limpiarlas.
    @account.conversations
            .where(contact_id: contact_id)
            .where('assignee_id IS DISTINCT FROM ?', user_id)
            .find_each do |conversation|
      Conversations::AssignmentService.new(conversation: conversation, assignee_id: user_id).perform
      count += 1
    rescue StandardError => e
      Rails.logger.error(
        "[ContactConversationAssignmentSync] failed | conversation=#{conversation.id} " \
        "user=#{user_id} #{e.class}: #{e.message}"
      )
    end
    count
  end
end
