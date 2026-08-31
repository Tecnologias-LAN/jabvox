# frozen_string_literal: true

# jabvox.order.update — actualiza SOLO lo configurado (estado, notas y/o líneas).
# Las líneas nuevas se SUMAN a las existentes; para editar una se indica su ID de
# línea y para borrarla se marca como eliminar.
class Jabvox::Flows::Nodes::Jabvox::OrderUpdateNode < Jabvox::Flows::Nodes::Jabvox::OrderBase
  type 'jabvox.order.update'
  label 'Actualizar Orden'

  def perform
    order = find_order!(param(:orderId))
    changes = update_attributes
    items = order_items
    fail_with!(nothing_to_update_message) if changes.empty? && items.empty?

    order.assign_attributes(changes)
    order.jabvox_order_items_attributes = items if items.any?
    compute_totals(order)
    order.save!
    order_view(order.reload)
  end

  private

  def update_attributes
    { status: first_filled(param(:status)), notes: first_filled(param(:notes)) }
      .reject { |_k, v| v.blank? }
  end

  def nothing_to_update_message
    'No se configuró nada que actualizar en la orden. Rellena el estado, las notas o al menos ' \
      'una línea.'
  end
end
