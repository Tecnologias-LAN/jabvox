require 'tiny_tds'

# SQL Server adapter (used e.g. for Wimpos). Connections are short-lived. SQL Server
# has no `SET TRANSACTION READ ONLY`, so read-only is enforced by:
#   - the upstream SqlValidatorService (blocks writes),
#   - a low LOCK_TIMEOUT + READ UNCOMMITTED isolation (never takes write locks),
#   - and the strong recommendation to use a login limited to db_datareader.
#
# Dialect specifics handled here (they differ from the pg/mysql/sqlite adapters):
#   - identifiers are quoted with [ ] (asymmetric), so quote_identifier is overridden.
#   - there is no LIMIT; the row cap is applied with SELECT TOP (n).
#   - pagination uses OFFSET ... FETCH (requires an ORDER BY).
#   - schema is read from INFORMATION_SCHEMA + sys.foreign_keys.
class Jabvox::Analytics::Adapters::SqlserverAdapter < Jabvox::Analytics::Adapters::BaseAdapter
  def dialect
    :sqlserver
  end

  # [ ] are asymmetric, so the base symmetric quoting can't be reused. We also escape
  # a literal ] by doubling it, per T-SQL rules.
  def quote_identifier(name)
    cleaned = name.to_s.gsub(/[^a-zA-Z0-9_.]/, '')
    cleaned.split('.').map { |part| "[#{part.gsub(']', ']]')}]" }.join('.')
  end

  def schema_introspection
    with_client do |client|
      cols = fetch_columns(client)
      pks = fetch_primary_keys(client)
      fks = fetch_foreign_keys(client)
      fetch_relations(client).map { |rel| build_relation(rel, cols, pks, fks) }
    end
  end

  def preview_table(options)
    per_page = row_cap(options.per_page)
    offset = ([options.page.to_i, 1].max - 1) * per_page
    qtable = quote_identifier(options.table)
    with_client do |client|
      cols = column_names(client, options.table)
      where = preview_where(options, cols) # ya viene con los valores inline (escapados)
      sql = preview_sql(qtable, options.order.presence || cols.first, offset, per_page, where)
      run_preview(client, sql, qtable, cols, where)
    end
  end

  def run_preview(client, sql, qtable, cols, where)
    rows = client.execute(sql).each.map(&:values)
    total = client.execute("SELECT COUNT(*) AS c FROM #{qtable}#{where}").each.first['c'].to_i
    Result.new(rows: rows, columns: cols, row_count: total, elapsed_ms: nil)
  end

  # WHERE para el preview: filtros exactos por columna + búsqueda de texto (LIKE) sobre todas
  # las columnas. tiny_tds no tiene binds server-side aquí, así que los valores se inline con
  # quote_value (mismo escapado que apply_binds usa para el query builder). Identificadores
  # citados. Sólo se filtra por columnas existentes.
  def preview_where(options, cols)
    clauses = preview_filter_pairs(options, cols).map do |col, values|
      list = values.map { |v| quote_value(v) }.join(', ')
      "#{quote_identifier(col)} IN (#{list})"
    end
    if options.search.present?
      like = quote_value("%#{options.search}%")
      ors = cols.map { |c| "CAST(#{quote_identifier(c)} AS NVARCHAR(MAX)) LIKE #{like}" }
      clauses << "(#{ors.join(' OR ')})"
    end
    clauses.any? ? " WHERE #{clauses.join(' AND ')}" : ''
  end

  # OFFSET/FETCH pagination needs an ORDER BY, so we always order (by the requested
  # column or the first one).
  def preview_sql(qtable, order_col, offset, per_page, where = '')
    "SELECT * FROM #{qtable}#{where} ORDER BY #{quote_identifier(order_col)} " \
      "OFFSET #{offset} ROWS FETCH NEXT #{per_page} ROWS ONLY"
  end

  def execute(sql, binds: [], row_limit: nil)
    cap = row_cap(row_limit)
    # No LIMIT in T-SQL: cap with TOP over the (already-validated) subquery.
    wrapped = "SELECT TOP (#{cap}) * FROM (#{subquery_body(sql)}) AS jabvox_sub"
    started = monotonic_ms
    with_client do |client|
      bound = apply_binds(wrapped, binds)
      result = client.execute(bound)
      rows = result.each.map(&:values)
      Result.new(rows: rows, columns: result.fields, row_count: rows.size, elapsed_ms: monotonic_ms - started)
    end
  end

  protected

  def probe(client)
    client.execute('SELECT 1').do
  end

  def with_client
    client = TinyTds::Client.new(connection_params)
    # Never block on write locks and never take shared read locks.
    client.execute("SET LOCK_TIMEOUT #{timeout_ms}").do
    client.execute('SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED').do
    yield client
  rescue TinyTds::Error => e
    raise ConnectionError, e.message
  ensure
    client&.close
  end

  private

  # tiny_tds has no server-side bind params for arbitrary statements, so we inline
  # the binds with proper quoting. Binds come only from the internal query builder
  # (never raw user SQL), and non-numeric values are single-quote-escaped.
  def apply_binds(sql, binds)
    return sql if binds.blank?

    result = sql.dup
    binds.each do |value|
      result = result.sub('?', quote_value(value))
    end
    result
  end

  def quote_value(value)
    case value
    when Numeric then value.to_s
    when true then '1'
    when false then '0'
    when nil then 'NULL'
    else "'#{value.to_s.gsub("'", "''")}'"
    end
  end

  def connection_params
    {
      host: data_source.host_jabvox,
      port: data_source.effective_port,
      username: data_source.username_jabvox,
      password: data_source.password_jabvox,
      database: data_source.database_jabvox,
      timeout: (timeout_ms / 1000.0).ceil,
      login_timeout: (timeout_ms / 1000.0).ceil
    }.compact
  end

  def column_names(client, table)
    client.execute("SELECT TOP (0) * FROM #{quote_identifier(table)}").fields
  end

  def build_relation(rel, cols, pks, fks)
    key = rel['name']
    {
      name: key,
      type: rel['kind'] == 'VIEW' ? :view : :table,
      columns: (cols[key] || []).map { |col| build_column(col, key, pks, fks) }
    }
  end

  def build_column(col, table_key, pks, fks)
    {
      name: col['column_name'],
      type: col['data_type'],
      nullable: col['is_nullable'] == 'YES',
      length: col['character_maximum_length'],
      primary_key: pks[table_key]&.include?(col['column_name']) || false,
      foreign_key: fks.dig(table_key, col['column_name'])
    }
  end

  def fetch_relations(client)
    client.execute(<<~SQL.squish).each.to_a
      SELECT TABLE_NAME AS name, TABLE_TYPE AS kind
      FROM INFORMATION_SCHEMA.TABLES
      WHERE TABLE_TYPE IN ('BASE TABLE', 'VIEW')
      ORDER BY TABLE_NAME
    SQL
  end

  def fetch_columns(client)
    rows = client.execute(<<~SQL.squish).each.to_a
      SELECT TABLE_NAME AS table_name, COLUMN_NAME AS column_name, DATA_TYPE AS data_type,
             IS_NULLABLE AS is_nullable, CHARACTER_MAXIMUM_LENGTH AS character_maximum_length
      FROM INFORMATION_SCHEMA.COLUMNS
      ORDER BY TABLE_NAME, ORDINAL_POSITION
    SQL
    rows.group_by { |r| r['table_name'] }
  end

  def fetch_primary_keys(client)
    rows = client.execute(<<~SQL.squish).each.to_a
      SELECT tc.TABLE_NAME AS table_name, kcu.COLUMN_NAME AS column_name
      FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
      JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE kcu
        ON tc.CONSTRAINT_NAME = kcu.CONSTRAINT_NAME
      WHERE tc.CONSTRAINT_TYPE = 'PRIMARY KEY'
    SQL
    rows.each_with_object({}) { |r, acc| (acc[r['table_name']] ||= []) << r['column_name'] }
  end

  def fetch_foreign_keys(client)
    rows = client.execute(<<~SQL.squish).each.to_a
      SELECT tp.name AS table_name, cp.name AS column_name,
             tr.name AS ref_table, cr.name AS ref_column
      FROM sys.foreign_keys fk
      JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
      JOIN sys.tables tp ON tp.object_id = fkc.parent_object_id
      JOIN sys.columns cp ON cp.object_id = fkc.parent_object_id AND cp.column_id = fkc.parent_column_id
      JOIN sys.tables tr ON tr.object_id = fkc.referenced_object_id
      JOIN sys.columns cr ON cr.object_id = fkc.referenced_object_id AND cr.column_id = fkc.referenced_column_id
    SQL
    rows.each_with_object({}) do |r, acc|
      (acc[r['table_name']] ||= {})[r['column_name']] = { table: r['ref_table'], column: r['ref_column'] }
    end
  end
end
