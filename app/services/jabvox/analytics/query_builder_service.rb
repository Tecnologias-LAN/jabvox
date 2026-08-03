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

  def initialize(adapter, spec)
    @adapter = adapter
    @spec = (spec || {}).deep_symbolize_keys
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

  def q(identifier)
    @adapter.quote_identifier(identifier)
  end

  def build_select
    parts = []
    parts << date_bucket_expr if date_bucket?
    Array(@spec[:columns]).each { |c| parts << q(c) }
    Array(@spec[:aggregations]).each { |agg| parts << aggregation_sql(agg) }
    raise InvalidSpec, 'Selecciona al menos una columna o agregación' if parts.empty?

    parts
  end

  def aggregation_sql(agg)
    fn = agg[:function].to_s.downcase
    raise InvalidSpec, "Agregación no soportada: #{fn}" unless AGGREGATIONS.include?(fn)

    col = fn == 'count' && agg[:column].blank? ? '*' : q(agg[:column])
    aliased = agg[:alias].present? ? " AS #{q(agg[:alias])}" : ''
    "#{fn.upcase}(#{col})#{aliased}"
  end

  def build_where
    binds = []
    clauses = Array(@spec[:filters]).filter_map do |f|
      next if f[:field].blank? || f[:operator].blank?

      op = OPERATOR_SQL[f[:operator].to_s]
      next unless op

      value = f[:operator].to_s == 'contains' ? "%#{f[:value]}%" : f[:value]
      value = "#{f[:value]}%" if f[:operator].to_s == 'starts_with'
      binds << value
      "#{q(f[:field])} #{op} #{placeholder(binds.size)}"
    end
    [clauses, binds]
  end

  def build_group_by
    parts = []
    parts << date_bucket_expr if date_bucket?
    parts << q(@spec[:group_by]) if @spec[:group_by].present?
    parts
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
