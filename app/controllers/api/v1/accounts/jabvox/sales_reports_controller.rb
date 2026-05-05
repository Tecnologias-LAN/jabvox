class Api::V1::Accounts::Jabvox::SalesReportsController < Api::V1::Accounts::Jabvox::BaseController
  before_action :check_authorization

  def show
    scope = build_scope
    render json: {
      summary: build_summary(scope),
      orders: build_orders_list(scope),
      by_product: build_by_product(scope),
      by_agent: build_by_agent(scope),
      by_status: build_by_status(scope)
    }
  end

  private

  def check_authorization
    authorize :jabvox_sales_report
  end

  # rubocop:disable Metrics/AbcSize
  def build_scope
    scope = Current.account.jabvox_orders
    if params[:date_from].present?
      scope = scope.where('jabvox_orders.created_at >= ?', safe_parse_date(params[:date_from]).beginning_of_day)
    end
    if params[:date_to].present?
      scope = scope.where('jabvox_orders.created_at <= ?', safe_parse_date(params[:date_to]).end_of_day)
    end
    scope = scope.where(doc_type: params[:doc_type]) if params[:doc_type].present?
    if params[:jabvox_product_id].present?
      item_ids = JabvoxOrderItem.where(jabvox_product_id: params[:jabvox_product_id]).select(:jabvox_order_id)
      scope = scope.where(id: item_ids)
    end
    scope
  end
  # rubocop:enable Metrics/AbcSize

  def safe_parse_date(str)
    Date.parse(str.to_s)
  rescue ArgumentError
    Date.today
  end

  def build_summary(scope)
    total_quotes = scope.where(doc_type: 'QUOTE').count
    total_sales  = scope.where(doc_type: 'SALE').count
    revenue      = scope.where(doc_type: 'SALE').sum(:total).to_f
    rate         = total_quotes.positive? ? (total_sales.to_f / total_quotes * 100).round(1) : 0
    { total_quotes: total_quotes, total_sales: total_sales, total_revenue: revenue.round(2), conversion_rate: rate }
  end

  # rubocop:disable Metrics/MethodLength
  def build_orders_list(scope)
    ids_sql = scope.select(:id).to_sql
    account_id = Current.account.id.to_i
    sql = <<~SQL.squish
      SELECT jo.id, jo.doc_type, jo.status, jo.total, jo.created_at AS date,
             u.name AS agent_name, ct.name AS contact_name
      FROM jabvox_orders jo
      LEFT JOIN conversations c ON c.id = jo.conversation_id AND c.account_id = #{account_id}
      LEFT JOIN users u ON u.id = c.assignee_id
      LEFT JOIN contacts ct ON ct.id = jo.contact_id
      WHERE jo.id IN (#{ids_sql})
      ORDER BY jo.created_at DESC
      LIMIT 500
    SQL
    ApplicationRecord.connection.execute(sql).map do |r|
      { id: r['id'].to_i, doc_type: r['doc_type'], status: r['status'],
        total: r['total'].to_f, date: r['date'], agent_name: r['agent_name'],
        contact_name: r['contact_name'] }
    end
  end
  # rubocop:enable Metrics/MethodLength

  def build_by_product(scope)
    JabvoxOrderItem
      .joins(:jabvox_order)
      .where(jabvox_order_id: scope.select(:id))
      .group(:jabvox_product_id, :name_snapshot)
      .select('jabvox_product_id AS product_id, name_snapshot AS name, ' \
              'SUM(line_total) AS revenue, SUM(quantity) AS quantity')
      .map { |r| { product_id: r.product_id, name: r.name, revenue: r.revenue.to_f.round(2), quantity: r.quantity.to_f.round(2) } }
      .sort_by { |r| -r[:revenue] }
  end

  # rubocop:disable Metrics/MethodLength
  def build_by_agent(scope)
    ids_sql = scope.select(:id).to_sql
    account_id = Current.account.id.to_i
    sql = <<~SQL.squish
      SELECT COALESCE(u.id, 0) AS agent_id, COALESCE(u.name, 'Sin asignar') AS name,
             COUNT(DISTINCT jo.id) AS count, COALESCE(SUM(jo.total), 0) AS revenue
      FROM jabvox_orders jo
      LEFT JOIN conversations c ON c.id = jo.conversation_id AND c.account_id = #{account_id}
      LEFT JOIN users u ON u.id = c.assignee_id
      WHERE jo.id IN (#{ids_sql})
      GROUP BY u.id, u.name
      ORDER BY revenue DESC
    SQL
    ApplicationRecord.connection.execute(sql).map do |r|
      { agent_id: r['agent_id'].to_i, name: r['name'], count: r['count'].to_i, revenue: r['revenue'].to_f.round(2) }
    end
  end
  # rubocop:enable Metrics/MethodLength

  def build_by_status(scope)
    labels = Current.account.jabvox_order_status_configs.index_by(&:key_jabvox)
    scope.group(:status).count.sort_by { |_, c| -c }.map do |status, count|
      { status: status, label: labels[status]&.label_jabvox || status, count: count }
    end
  end
end
