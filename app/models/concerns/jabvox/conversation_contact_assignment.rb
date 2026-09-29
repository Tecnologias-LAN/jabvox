# Mantiene sincronizado el responsable del CONTACTO con el de su conversación: la
# conversación es la fuente de verdad, y tanto la lista de contactos como Kanban filtran por
# `contacts.assignee_id`. Sin esto, asignar una conversación no haría visible el contacto al
# agente en esas pantallas.
#
# Refleja en ambos sentidos: asignar la conversación asigna el contacto, y DESASIGNARLA lo
# desasigna también. Cubre todas las vías de asignación —manual, API, masiva y automática—
# porque engancha el modelo, no el controlador.
#
# Antes esto sincronizaba el lead del contacto; al retirar Leads, el destino pasa a ser el
# propio contacto, que es donde ya vive `assignee_id`.
module Jabvox::ConversationContactAssignment
  extend ActiveSupport::Concern

  included do
    after_commit :jabvox_sync_contact_assignee
  end

  private

  def jabvox_sync_contact_assignee
    return unless saved_change_to_assignee_id?
    return if contact.blank?
    return if contact.assignee_id == assignee_id

    # assignee_id puede ser nil aquí (conversación desasignada) → se refleja igual.
    contact.update!(assignee_id: assignee_id)
  rescue StandardError => e
    # Nunca romper el flujo de asignación en sí; se registra y se sigue.
    Rails.logger.error("[Jabvox] sync de responsable del contacto falló en conversación #{id}: #{e.message}")
  end
end
