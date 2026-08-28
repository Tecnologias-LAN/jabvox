# Compiles a structured visual-query spec into dialect-correct, parameterized SQL.
# Identifiers are quoted/sanitized through the adapter; all literal values are passed as binds.
#
# spec = {
#   table: 'orders',
#   columns: ['status', 'total'],
#   aggregations: [{ function: 'sum', column: 'total', alias: 'total_sum' }],
#   filters: [{ field: 'status', operator: 'eq', value: 'paid' }],
#   group_by: 'status',
#   date_bucket: { column: 'created_at', unit: 'month' }
# }
#
#   sql, binds = Jabvox::Analytics::QueryBuilderService.new(adapter, spec).build
class Jabvox::Analytics::QueryBuilderService
  AGGREGATIONS = %w[count sum avg min max].freeze
  DATE_UNITS = %w[day week month year].freeze
  OPERATOR_SQL = {
    'eq' => '=', 'neq' => '!=', 'gt' => '>', 'gte' => '>=', 'lt' => '<', 'lte' => '<=',
    'contains' => 'LIKE', 'starts_with' => 'LIKE'
  }.freeze

  InvalidSpec = Class.new(StandardError)

  # The frontend is inconsistent: the visual builder sends camelCase (groupBy/dateBucket)
  # while the data viewer sends snake_case (group_by/date_bucket). Normalize both to the
  # snake_case keys this service reads, so GROUP BY is never silently dropped.
  KEY_ALIASES = { groupBy: :group_by, dateBucket: :date_bucket }.freeze

  def initialize(adapter, spec)
    @adapter = adapter
    @spec = normalize_keys((spec || {}).deep_symbolize_keys)
  end

  def build
    raise InvalidSpec, 'Falta la tabla' if @spec[:table].blank?

    select = build_select
    where, binds = build_where
    group = build_group_by
    sql = "SELECT #{select.join(', ')} FROM #{q(@spec[:table])}"
    sql << " WHERE #{where.join(' AND ')}" if where.any?
    sql << " GROUP BY #{group.join(', ')}" if group.any?
    [sql, binds]
  end

  private

  def normalize_keys(spec)
    KEY_ALIASES.each do |camel, snake|
      spec[snake] = spec.delete(camel) if spec.key?(camel) && spec[snake].blank?
    end
    spec
  end

  def q(identifier)
    @adapter.quote_identifier(identifier)
  end

  def build_select
    parts = []
    # La expresión de fecha lleva alias en el SELECT (p.ej. AS [periodo]). Sin alias, SQL Server
    # rechaza la columna al envolver la consulta en una derived table (jabvox_sub).
    parts << "#{date_bucket_expr} AS #{q(date_bucket_alias)}" if date_bucket?
    parts << q(auto_group_column) if auto_group_column
    Array(@spec[:columns]).each { |c| parts << q(c) }
    Array(@spec[:aggregations]).each { |agg| parts << aggregation_sql(agg) }
    raise InvalidSpec, 'Selecciona al menos una columna o agregación' if parts.empty?

    parts
  end

  # Al agrupar, la columna de agrupación se incluye en el SELECT automáticamente (como
  # Metabase) para que la fila muestre a qué grupo (p.ej. tienda) pertenece. Devuelve nil
  # si no hay group_by o si ya está en las columnas seleccionadas.
  # Alias legible para la columna de fecha agrupada (p.ej. Fecha por 'month' → "Fecha_month").
  def date_bucket_alias
    "#{@spec.dig(:date_bucket, :column)}_#{@spec.dig(:date_bucket, :unit)}"
  end

  def auto_group_column
    grouped = @spec[:group_by].to_s
    return nil if grouped.blank?

    listed = Array(@spec[:columns]).map(&:to_s)
    listed.include?(grouped) ? nil : grouped
  end

  def aggregation_sql(agg)
    # The frontend sends the function under :fn ({ fn: 'COUNT', column }); older/API
    # callers use :function. Accept both.
    func = (agg[:function].presence || agg[:fn]).to_s.downcase
    raise InvalidSpec, "Agregación no soportada: #{func}" unless AGGREGATIONS.include?(func)

    col = func == 'count' && agg[:column].blank? ? '*' : q(agg[:column])
    "#{func.upcase}(#{col}) AS #{q(aggregation_alias(agg, func))}"
  end

  # Every aggregation gets a name. An explicit alias wins; otherwise we derive one
  # (like Metabase: "sum_total", "count"). This is not cosmetic: SQL Server wraps the
  # query in a derived table (… AS jabvox_sub) and rejects unnamed columns there.
  def aggregation_alias(agg, func)
    return agg[:alias] if agg[:alias].present?

    agg[:column].blank? ? func : "#{func}_#{agg[:column]}"
  end

  def build_where
    binds = []
    clauses = Array(@spec[:filters]).filter_map { |f| where_clause(f, binds) }
    [clauses, binds]
  end

  # Una cláusula WHERE (o nil si el filtro es inválido). Muta `binds` agregando los valores.
  # Soporta filtro por lista de valores (multi-selección → IN) y por operador simple.
  def where_clause(filter, binds)
    return nil if filter[:field].blank?

    values = filter_values(filter)
    return in_clause(filter[:field], values, binds) unless values.nil?

    simple_clause(filter, binds)
  end

  def in_clause(field, values, binds)
    return nil if values.empty?

    placeholders = values.map do |v|
      binds << v
      placeholder(binds.size)
    end
    "#{q(field)} IN (#{placeholders.join(', ')})"
  end

  def simple_clause(filter, binds)
    op = OPERATOR_SQL[filter[:operator].to_s]
    return nil unless op

    value = filter[:operator].to_s == 'contains' ? "%#{filter[:value]}%" : filter[:value]
    value = "#{filter[:value]}%" if filter[:operator].to_s == 'starts_with'
    binds << value
    "#{q(filter[:field])} #{op} #{placeholder(binds.size)}"
  end

  # Devuelve la lista de valores si el filtro es de tipo lista (operador 'in' o clave :values),
  # o nil si es un filtro de operador simple. Acepta values como Array o Hash indexado.
  def filter_values(filter)
    return nil unless filter[:operator].to_s == 'in' || filter.key?(:values)

    raw = filter[:values]
    list = raw.is_a?(Hash) ? raw.values : Array(raw)
    list.reject { |v| v.nil? || v.to_s.empty? }
  end

  def build_group_by
    parts = []
    parts << date_bucket_expr if date_bucket?
    parts << q(@spec[:group_by]) if @spec[:group_by].present?
    # Regla SQL: si hay agregaciones, toda columna no agregada del SELECT debe ir en el
    # GROUP BY. Esto habilita dimensiones múltiples (p.ej. heatmap: 2 dimensiones + 1 medida,
    # o tablas resumen con varias columnas categóricas y una métrica).
    if aggregations?
      already = parts.dup
      Array(@spec[:columns]).each do |col|
        quoted = q(col)
        parts << quoted unless already.include?(quoted) || quoted == q(@spec[:group_by].to_s)
      end
    end
    parts
  end

  def aggregations?
    Array(@spec[:aggregations]).any? { |agg| (agg[:function].presence || agg[:fn]).present? }
  end

  def date_bucket?
    @spec[:date_bucket].is_a?(Hash) && @spec.dig(:date_bucket, :column).present?
  end

  def date_bucket_expr
    col = q(@spec.dig(:date_bucket, :column))
    unit = @spec.dig(:date_bucket, :unit).to_s
    raise InvalidSpec, "Unidad de fecha no soportada: #{unit}" unless DATE_UNITS.include?(unit)

    case @adapter.dialect
    when :postgres
      "DATE_TRUNC('#{unit}', #{col})"
    when :mysql
      mysql_date_bucket(col, unit)
    when :sqlserver
      sqlserver_date_bucket(col, unit)
    else # sqlite
      sqlite_date_bucket(col, unit)
    end
  end

  # T-SQL has no DATE_TRUNC. Truncate by casting to date (day) or rebuilding the
  # date at the period boundary with DATEFROMPARTS/DATEADD.
  def sqlserver_date_bucket(col, unit)
    case unit
    when 'day' then "CAST(#{col} AS date)"
    when 'week' then "CAST(DATEADD(DAY, -((DATEPART(WEEKDAY, #{col}) + 5) % 7), #{col}) AS date)"
    when 'month' then "DATEFROMPARTS(YEAR(#{col}), MONTH(#{col}), 1)"
    when 'year' then "DATEFROMPARTS(YEAR(#{col}), 1, 1)"
    end
  end

  def mysql_date_bucket(col, unit)
    case unit
    when 'day' then "DATE(#{col})"
    when 'week' then "DATE_SUB(DATE(#{col}), INTERVAL WEEKDAY(#{col}) DAY)"
    when 'month' then "DATE_FORMAT(#{col}, '%Y-%m-01')"
    when 'year' then "DATE_FORMAT(#{col}, '%Y-01-01')"
    end
  end

  def sqlite_date_bucket(col, unit)
    case unit
    when 'day' then "DATE(#{col})"
    when 'week' then "DATE(#{col}, 'weekday 0', '-6 days')"
    when 'month' then "STRFTIME('%Y-%m-01', #{col})"
    when 'year' then "STRFTIME('%Y-01-01', #{col})"
    end
  end

  # Postgres/SQLite use $n? No — pg uses $1, mysql/sqlite use ?. The adapters' execute()
  # handles binds positionally; emit the dialect placeholder.
  def placeholder(index)
    @adapter.dialect == :postgres ? "$#{index}" : '?'
  end
end
