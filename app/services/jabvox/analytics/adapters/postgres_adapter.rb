require 'pg'

# PostgreSQL adapter. Connections are short-lived and forced read-only at the session level:
#   SET default_transaction_read_only = on; SET statement_timeout = <ms>
# and every statement runs inside a `BEGIN READ ONLY ... COMMIT` transaction, so a write is
# rejected by the server even if upstream SQL validation were bypassed.
class Jabvox::Analytics::Adapters::PostgresAdapter < Jabvox::Analytics::Adapters::BaseAdapter
  def dialect
    :postgres
  end

  def schema_introspection
    with_client do |conn|
      meta = { columns: fetch_columns(conn), pks: fetch_primary_keys(conn), fks: fetch_foreign_keys(conn) }
      fetch_relations(conn).map { |rel| build_relation(rel, meta) }
    end
  end

  def preview_table(options)
    per_page = row_cap(options.per_page)
    offset = ([options.page.to_i, 1].max - 1) * per_page
    qtable = quote_identifier(options.table)
    order_sql = options.order.present? ? "ORDER BY #{quote_identifier(options.order)}" : ''

    with_client do |conn|
      cols = conn.exec("SELECT * FROM #{qtable} LIMIT 0").fields
      where, binds = preview_where(options, cols)
      ctx = { qtable: qtable, cols: cols, where: where, binds: binds,
              order_sql: order_sql, per_page: per_page, offset: offset }
      run_preview(conn, ctx)
    end
  end

  def run_preview(conn, ctx)
    qtable, where, binds = ctx.values_at(:qtable, :where, :binds)
    sql = "SELECT * FROM #{qtable}#{where} #{ctx[:order_sql]} " \
          "LIMIT $#{binds.size + 1} OFFSET $#{binds.size + 2}"
    result = conn.exec_params(sql, binds + [ctx[:per_page], ctx[:offset]])
    total = conn.exec_params("SELECT COUNT(*) AS c FROM #{qtable}#{where}", binds).first['c'].to_i
    Result.new(rows: result.values, columns: ctx[:cols], row_count: total, elapsed_ms: nil)
  end

  # WHERE para el preview: filtros por columna (uno o varios valores → IN) + búsqueda de texto
  # (search) sobre todas las columnas con ILIKE. Identificadores citados, valores por bind ($n).
  def preview_where(options, cols)
    binds = []
    clauses = preview_filter_pairs(options, cols).map do |col, values|
      placeholders = values.map do |v|
        binds << v
        "$#{binds.size}"
      end
      "#{quote_identifier(col)} IN (#{placeholders.join(', ')})"
    end
    if options.search.present?
      binds << "%#{options.search}%"
      ors = cols.map { |c| "CAST(#{quote_identifier(c)} AS TEXT) ILIKE $#{binds.size}" }
      clauses << "(#{ors.join(' OR ')})"
    end
    [clauses.any? ? " WHERE #{clauses.join(' AND ')}" : '', binds]
  end

  def execute(sql, binds: [], row_limit: nil)
    cap = row_cap(row_limit)
    wrapped = "SELECT * FROM (#{sql}) AS jabvox_sub LIMIT #{cap}"
    started = monotonic_ms
    with_client do |conn|
      result = binds.any? ? conn.exec_params(wrapped, binds) : conn.exec(wrapped)
      Result.new(rows: result.values, columns: result.fields, row_count: result.ntuples, elapsed_ms: monotonic_ms - started)
    end
  end

  protected

  def probe(conn)
    conn.exec('SELECT 1')
  end

  def with_client
    conn = PG.connect(connection_params)
    conn.exec("SET statement_timeout = #{timeout_ms}")
    conn.exec('SET default_transaction_read_only = on')
    conn.exec('BEGIN READ ONLY')
    result = yield conn
    conn.exec('COMMIT')
    result
  rescue PG::Error => e
    raise ConnectionError, e.message
  ensure
    conn&.close
  end

  private

  def connection_params
    {
      host: data_source.host_jabvox,
      port: data_source.effective_port,
      user: data_source.username_jabvox,
      password: data_source.password_jabvox,
      dbname: data_source.database_jabvox,
      connect_timeout: (timeout_ms / 1000.0).ceil,
      sslmode: data_source.ssl_mode_jabvox.presence || 'prefer'
    }.compact
  end

  def build_relation(rel, meta)
    key = rel['name']
    {
      name: key,
      type: rel['kind'] == 'v' ? :view : :table,
      columns: (meta[:columns][key] || []).map { |col| build_column(col, key, meta) }
    }
  end

  def build_column(col, table_key, meta)
    {
      name: col['column_name'],
      type: col['data_type'],
      nullable: col['is_nullable'] == 'YES',
      length: col['character_maximum_length'],
      primary_key: meta[:pks][table_key]&.include?(col['column_name']) || false,
      foreign_key: meta[:fks].dig(table_key, col['column_name'])
    }
  end

  def fetch_relations(conn)
    conn.exec(<<~SQL.squish)
      SELECT c.relname AS name, c.relkind AS kind
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE c.relkind IN ('r', 'v', 'm')
        AND n.nspname NOT IN ('pg_catalog', 'information_schema')
      ORDER BY c.relname
    SQL
  end

  def fetch_columns(conn)
    rows = conn.exec(<<~SQL.squish)
      SELECT table_name, column_name, data_type, is_nullable, character_maximum_length
      FROM information_schema.columns
      WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
      ORDER BY table_name, ordinal_position
    SQL
    rows.group_by { |r| r['table_name'] }
  end

  def fetch_primary_keys(conn)
    rows = conn.exec(<<~SQL.squish)
      SELECT tc.table_name, kcu.column_name
      FROM information_schema.table_constraints tc
      JOIN information_schema.key_column_usage kcu
        ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
      WHERE tc.constraint_type = 'PRIMARY KEY'
    SQL
    rows.each_with_object({}) { |r, acc| (acc[r['table_name']] ||= []) << r['column_name'] }
  end

  def fetch_foreign_keys(conn)
    rows = conn.exec(<<~SQL.squish)
      SELECT tc.table_name, kcu.column_name, ccu.table_name AS ref_table, ccu.column_name AS ref_column
      FROM information_schema.table_constraints tc
      JOIN information_schema.key_column_usage kcu
        ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
      JOIN information_schema.constraint_column_usage ccu
        ON ccu.constraint_name = tc.constraint_name AND ccu.table_schema = tc.table_schema
      WHERE tc.constraint_type = 'FOREIGN KEY'
    SQL
    rows.each_with_object({}) do |r, acc|
      (acc[r['table_name']] ||= {})[r['column_name']] = { table: r['ref_table'], column: r['ref_column'] }
    end
  end
end
