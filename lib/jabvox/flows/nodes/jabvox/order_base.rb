# frozen_string_literal: true

# Base común de los nodos `jabvox.order.*`: normaliza las LÍNEAS y recalcula los
# totales igual que `orders_controller#compute_totals`.
class Jabvox::Flows::Nodes::Jabvox::OrderBase < Jabvox::Flows::Nodes::Jabvox::Base
  private

  def find_order!(raw, label = 'el ID de la orden')
    order_id = require_id!(raw, label)
    order = account.jabvox_orders.find_by(id: order_id)
    return order if order

    fail_with!("La orden #{order_id} no existe en esta cuenta. Comprueba el ID; si viene del nodo " \
               '"Crear Orden", revisa que ese paso siga devolviéndolo.')
  end

  # Líneas desde el editor del nodo o desde un JSON escrito a mano. Cada error
  # dice el NÚMERO de línea para poder corregirla sin adivinar.
  def order_items
    raw = param(:items)
    return [] if blank_param?(raw)

    list = raw.is_a?(String) ? parse_items_json(raw) : raw
    fail_with!('Las líneas de la orden deben ser una lista. Usa el editor de líneas del nodo.') unless list.is_a?(Array)

    list.each_with_index.map { |entry, index| normalize_item(entry, index + 1) }
  end

  def items_configured?
    !blank_param?(param(:items)) && order_items.any?
  end

  def parse_items_json(text)
    JSON.parse(text.strip)
  rescue JSON::ParserError
    fail_with!('Las líneas de la orden no son un JSON válido. Usa el editor de líneas del nodo.')
  end

  def normalize_item(entry, number)
    unless entry.is_a?(Hash)
      fail_with!("La línea #{number} de la orden no es válida: se esperaba un objeto con producto, " \
                 'cantidad y precio.')
    end

    item = entry.deep_stringify_keys
    return destroy_item(item, number) if opt_in?(first_filled(item['_destroy'], item['destroy']))

    build_item(item, number)
  end

  # Marcar para borrar solo tiene sentido sobre una línea que YA existe.
  def destroy_item(item, number)
    line_id = num_or_nil(item['id'])
    if line_id.nil?
      fail_with!("La línea #{number} está marcada para eliminar pero no tiene ID de línea. Solo se " \
                 'pueden eliminar líneas que ya existen en la orden.')
    end

    { 'id' => line_id.to_i, '_destroy' => true }
  end

  def build_item(item, number)
    name = first_filled(item['name_snapshot'], item['name'])
    if name.blank?
      fail_with!("La línea #{number} no tiene producto ni descripción. Elige un producto en el editor " \
                 'de líneas.')
    end

    { 'name_snapshot' => name, 'quantity' => quantity(item, number, name),
      'unit_price' => unit_price(item, number, name),
      'discount_pct' => pct(item, %w[discount_pct discountPct], 'descuento', number, name),
      'tax_pct' => pct(item, %w[tax_pct taxPct], 'impuesto', number, name) }
      .merge(optional_ids(item))
  end

  def optional_ids(item)
    ids = {}
    line_id = num_or_nil(item['id'])
    ids['id'] = line_id.to_i if line_id
    product_id = num_or_nil(first_filled(item['jabvox_product_id'], item['productId'], item['product_id']))
    ids['jabvox_product_id'] = product_id.to_i if product_id
    ids
  end

  def quantity(item, number, name)
    value = num_or_nil(item['quantity'])
    return 1 if value.nil?
    return value if value.positive?

    fail_with!("La cantidad de la línea #{number} (\"#{name}\") debe ser mayor que 0.")
  end

  def unit_price(item, number, name)
    value = num_or_nil(first_filled(item['unit_price'], item['unitPrice']))
    return 0 if value.nil?
    return value unless value.negative?

    fail_with!("El precio de la línea #{number} (\"#{name}\") no puede ser negativo.")
  end

  def pct(item, keys, label, number, name)
    value = num_or_nil(first_filled(*keys.map { |k| item[k] }))
    return 0 if value.nil?
    return value if value.between?(0, 100)

    fail_with!("El #{label} de la línea #{number} (\"#{name}\") debe estar entre 0 y 100.")
  end

  def num_or_nil(value)
    return nil if blank_param?(value)

    number = Float(value.to_s)
    number.finite? ? number : nil
  rescue ArgumentError, TypeError
    nil
  end

  # Mismos cálculos que el panel: subtotal − descuento + impuesto.
  def compute_totals(order)
    items = order.jabvox_order_items.reject(&:marked_for_destruction?)
    items.each { |i| i.line_total = line_base(i) - line_pct(i, i.discount_pct) + line_pct(i, i.tax_pct) }
    assign_totals(order, items)
  end

  def assign_totals(order, items)
    order.subtotal = items.sum { |i| line_base(i) }
    order.discount_total = items.sum { |i| line_pct(i, i.discount_pct) }
    order.tax_total = items.sum { |i| line_pct(i, i.tax_pct) }
    order.total = order.subtotal - order.discount_total + order.tax_total
  end

  def line_base(item)
    item.unit_price.to_f * item.quantity.to_f
  end

  def line_pct(item, pct_value)
    line_base(item) * (pct_value.to_f / 100.0)
  end

  def order_view(order)
    { 'id' => order.id, 'orderId' => order.id, 'doc_type' => order.doc_type,
      'status' => order.status, 'notes' => order.notes,
      'contact_id' => order.contact_id, 'conversation_id' => order.conversation_id,
      'subtotal' => order.subtotal.to_f, 'discount_total' => order.discount_total.to_f,
      'tax_total' => order.tax_total.to_f, 'total' => order.total.to_f,
      'items' => order.jabvox_order_items.map { |i| item_view(i) } }
  end

  def item_view(item)
    { 'id' => item.id, 'jabvox_product_id' => item.jabvox_product_id,
      'name_snapshot' => item.name_snapshot, 'quantity' => item.quantity.to_f,
      'unit_price' => item.unit_price.to_f, 'discount_pct' => item.discount_pct.to_f,
      'tax_pct' => item.tax_pct.to_f, 'line_total' => item.line_total.to_f }
  end
end
