# frozen_string_literal: true

# jabvox.order.create — crea una orden/cotización con sus líneas. El controller
# original NO comprobaba que el contacto fuera de la cuenta: la orden se guardaba
# con el contacto de OTRO tenant. Aquí se valida antes de crear nada.
class Jabvox::Flows::Nodes::Jabvox::OrderCreateNode < Jabvox::Flows::Nodes::Jabvox::OrderBase
  type 'jabvox.order.create'
  label 'Crear Orden'

  def perform
    order = account.jabvox_orders.new(create_attributes)
    order.jabvox_order_items_attributes = order_items if order_items.any?
    compute_totals(order)
    order.save!
    order_view(order.reload)
  end

  private

  def create_attributes
    { doc_type: doc_type, contact_id: linked_contact&.id,
      conversation_id: linked_conversation&.id,
      notes: first_filled(param(:notes)).presence }.merge(status_attribute)
  end

  # Sin estado la orden se crea como "draft", que es el default del modelo.
  def status_attribute
    status = first_filled(param(:status))
    status.blank? ? {} : { status: status }
  end

  def doc_type
    raw = first_filled(param(:doc_type), param(:docType), 'QUOTE').upcase
    return raw if JabvoxOrder::DOC_TYPES.include?(raw)

    fail_with!("Tipo de documento no válido: \"#{raw}\". Usa QUOTE (Cotización) o SALE (Venta).")
  end

  def linked_contact
    raw = first_filled(param(:contactId))
    raw.present? ? find_contact!(raw) : nil
  end

  # El ID INTERNO de la conversación, no el número visible: así lo dice el catálogo.
  def linked_conversation
    raw = first_filled(param(:conversationId))
    return nil if raw.blank?

    conversation = account.conversations.find_by(id: raw)
    return conversation if conversation

    fail_with!("La conversación #{raw} no existe en esta cuenta. Aquí va el ID INTERNO de la " \
               'conversación, no el número visible.')
  end
end
