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
class Jabvox::Analytics::Adapters::SqlserverAdapter < Jabvox::Analytics::Adapters::BaseAdapter # rubocop:disable Metrics/ClassLength
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
    wrapped = "SELECT TOP (#{cap}) * FROM (#{allow_order_by_in_subquery(subquery_body(sql))}) AS jabvox_sub"
    started = monotonic_ms
    with_client do |client|
      bound = apply_binds(wrapped, binds)
      result = client.execute(bound)
      rows = result.each.map(&:values)
      Result.new(rows: rows, columns: result.fields, row_count: rows.size, elapsed_ms: monotonic_ms - started)
    end
  end

  protected

  # T-SQL rejects an ORDER BY inside a derived table/view unless that same query
  # also has its own TOP/OFFSET/FOR XML — and the user's query here always ends
  # up as the derived table inside execute's own "SELECT TOP (cap) * FROM (...)"
  # wrapper. A plain "SELECT ... ORDER BY x" that works fine standalone then
  # fails only once wrapped, with "The ORDER BY clause is invalid in views,
  # inline functions, derived tables...".
  #
  # Fixed by giving the query its own TOP, which SQL Server accepts alongside
  # an ORDER BY in a derived table. "TOP 100 PERCENT" (added only when the
  # query doesn't already have TOP/OFFSET/FOR XML of its own) is the standard
  # trick for this and changes nothing when there's no existing TOP — but a
  # query that ALREADY has "TOP n ... ORDER BY" (the one real case here: "TOP 3
  # ... ORDER BY total DESC", to answer "top 3 by X") must keep that n as-is:
  # inserting 100 PERCENT there, or moving the ORDER BY elsewhere, both change
  # which n rows the query actually returns, not just silence the DB error.
  HAS_OFFSET_OR_XML = /\bOFFSET\s+\d|\bFOR\s+XML\b/i
  OUTER_SELECT = /(\bSELECT\s+(?:DISTINCT\s+)?)(TOP\s*\(?\s*\d)?/i

  def allow_order_by_in_subquery(sql)
    return sql unless sql.match?(/\bORDER\s+BY\b/i)
    return sql if sql.match?(HAS_OFFSET_OR_XML)

    pos = final_select_position(sql)
    return sql if pos.nil?

    after = sql[pos..]
    match = after.match(OUTER_SELECT)
    return sql if match.nil?
    return sql if match[2] # ya tiene TOP n — no tocar

    prefix = sql[0...pos]
    prefix + after.sub(/\A(\s*SELECT\s+(?:DISTINCT\s+)?)/i, '\1TOP 100 PERCENT ')
  end

  def final_select_position(sql)
    return 0 unless sql.match?(/\A\s*WITH\b/i)

    pos = cte_end_position(sql)
    pos ? pos + sql[pos..].index(/SELECT/i).to_i : nil
  end

  def cte_end_position(sql)
    depth = 0
    sql.each_char.with_index do |ch, i|
      depth += 1 if ch == '('
      depth -= 1 if ch == ')'
      return i if depth.zero? && sql[i..].match?(/\A\s*SELECT\b/i)
    end
    nil
  end

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
