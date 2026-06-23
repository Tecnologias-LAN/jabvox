# frozen_string_literal: true

# Reporte interno "Ventas" (key: sales).
#
# Fuentes (todas con scoping obligatorio por cuenta vía ActiveRecord):
#   - jabvox_orders       (account.jabvox_orders)   -> doc_type SALE/QUOTE, status, total, subtotal, tax_total, contact_id
#   - jabvox_order_items  (vía jabvox_order_id -> jabvox_orders.account_id)
#   - jabvox_products     (account.jabvox_products)
#
# Notas de esquema:
#   - jabvox_orders NO tiene FK a usuario/agente/vendedor; solo contact_id (cliente).
#     Por eso la sección de desglose por agente queda marcada como no disponible.
#   - jabvox_order_items NO tiene account_id propia; el scoping se hereda del pedido.
class Jabvox::Analytics::Reports::SalesReportService
  SALE = 'SALE'
  QUOTE = 'QUOTE'

  def initialize(account:, date_from: nil, date_to: nil, filters: {})
    raise ArgumentError, 'account is required' if account.nil?

    @account = account
    @date_from = date_from
    @date_to = date_to
    @filters = filters || {}
  end

  def call
    {
      summary: summary,
      series: series,
      by_status: by_status,
      by_doc_type: by_doc_type,
      top_products: top_products,
      top_contacts: top_contacts,
      by_agent: by_agent_unavailable
    }
  end

  private

  attr_reader :account, :date_from, :date_to, :filters

  # Pedidos de la cuenta acotados por created_at. Siempre arranca de la asociación de la cuenta.
  # Filtros: status y contact_id. NO se filtra por doc_type aquí porque el reporte
  # divide internamente en SALE/QUOTE (aplicarlo rompería esa separación); jabvox_orders
  # no tiene FK de agente/usuario, así que agent_id no aplica.
  def scoped_orders
    relation = account.jabvox_orders
    relation = relation.where('jabvox_orders.created_at >= ?', date_from) if date_from.present?
    relation = relation.where('jabvox_orders.created_at <= ?', date_to) if date_to.present?
    relation = relation.where(status: filters['status']) if filters['status'].present?
    relation = relation.where(contact_id: filters['contact_id'].to_i) if filters['contact_id'].present?
    relation
  end

  def sales_orders
    scoped_orders.where(doc_type: SALE)
  end

  def quote_orders
    scoped_orders.where(doc_type: QUOTE)
  end

  def summary
    {
      orders_count: scoped_orders.count,
      sales_count: sales_orders.count,
      quotes_count: quote_orders.count,
      sales_total: sales_orders.sum(:total).to_f,
      sales_subtotal: sales_orders.sum(:subtotal).to_f,
      sales_tax_total: sales_orders.sum(:tax_total).to_f,
      sales_discount_total: sales_orders.sum(:discount_total).to_f,
      quotes_total: quote_orders.sum(:total).to_f,
      average_sale_ticket: average_sale_ticket,
      quote_to_sale_rate: quote_to_sale_rate
    }
  end

  def average_sale_ticket
    count = sales_orders.count
    return 0.0 if count.zero?

    (sales_orders.sum(:total).to_f / count).round(2)
  end

  # Tasa de conversión simple: ventas / (ventas + cotizaciones).
  def quote_to_sale_rate
    sales = sales_orders.count
    quotes = quote_orders.count
    denominator = sales + quotes
    return 0.0 if denominator.zero?

    (sales.to_f / denominator).round(4)
  end

  # Serie temporal diaria de ventas (solo doc_type SALE) por fecha de creación.
  def series
    rows = sales_orders
           .group('DATE(jabvox_orders.created_at)')
           .order(Arel.sql('DATE(jabvox_orders.created_at)'))
           .pluck(Arel.sql('DATE(jabvox_orders.created_at)'), Arel.sql('COUNT(*)'), Arel.sql('COALESCE(SUM(total), 0)'))

    rows.map do |date, count, total|
      { date: date.to_s, sales_count: count, sales_total: total.to_f }
    end
  end

  # Desglose por estado configurable (status), considerando todos los documentos.
  def by_status
    scoped_orders
      .group(:status)
      .pluck(:status, Arel.sql('COUNT(*)'), Arel.sql('COALESCE(SUM(total), 0)'))
      .map { |status, count, total| { status: status, count: count, total: total.to_f } }
  end

  def by_doc_type
    scoped_orders
      .group(:doc_type)
      .pluck(:doc_type, Arel.sql('COUNT(*)'), Arel.sql('COALESCE(SUM(total), 0)'))
      .map { |doc_type, count, total| { doc_type: doc_type, count: count, total: total.to_f } }
  end

  # Top productos por ingreso, a partir de las líneas de pedidos de VENTA de la cuenta.
  # Scoping por cuenta vía join a jabvox_orders (que pertenece a la cuenta) + merge(sales_orders).
  def top_products
    rows = JabvoxOrderItem
           .joins(:jabvox_order)
           .merge(sales_orders)
           .group('jabvox_order_items.jabvox_product_id', 'jabvox_order_items.name_snapshot')
           .order(Arel.sql('SUM(jabvox_order_items.line_total) DESC'))
           .limit(10)
           .pluck(
             'jabvox_order_items.jabvox_product_id',
             'jabvox_order_items.name_snapshot',
             Arel.sql('COALESCE(SUM(jabvox_order_items.quantity), 0)'),
             Arel.sql('COALESCE(SUM(jabvox_order_items.line_total), 0)')
           )

    rows.map do |product_id, name, quantity, revenue|
      { product_id: product_id, name: name, quantity: quantity.to_f, revenue: revenue.to_f }
    end
  end

  # Top contactos (clientes) por monto vendido. Es el único actor disponible en jabvox_orders.
  def top_contacts
    sales_orders
      .where.not(contact_id: nil)
      .group(:contact_id)
      .order(Arel.sql('SUM(total) DESC'))
      .limit(10)
      .pluck(:contact_id, Arel.sql('COUNT(*)'), Arel.sql('COALESCE(SUM(total), 0)'))
      .map { |contact_id, count, total| { contact_id: contact_id, sales_count: count, total: total.to_f } }
  end

  # TODO: jabvox_orders no tiene FK a usuario/agente/vendedor (no existe user_id/agent_id/assignee_id).
  # No se puede calcular ventas por agente con el esquema actual. Si se añade la columna, implementar aquí.
  def by_agent_unavailable
    { available: false, reason: 'jabvox_orders has no user/agent/assignee FK; only contact_id (customer) exists' }
  end
end
