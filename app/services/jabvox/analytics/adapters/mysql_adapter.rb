require 'mysql2'

# MySQL / MariaDB adapter. Connections are short-lived and forced read-only at the session
# level (SET SESSION TRANSACTION READ ONLY + max_execution_time) and each statement runs in
# a read-only transaction, so writes are rejected server-side regardless of upstream checks.
class Jabvox::Analytics::Adapters::MysqlAdapter < Jabvox::Analytics::Adapters::BaseAdapter
  def dialect
    :mysql
  end

  def schema_introspection
    db = data_source.database_jabvox
    with_client do |client|
      meta = { columns: fetch_columns(client, db), fks: fetch_foreign_keys(client, db) }
      fetch_relations(client, db).map { |rel| build_relation(rel, meta) }
    end
  end

  def preview_table(options)
    per_page = row_cap(options.per_page)
    offset = ([options.page.to_i, 1].max - 1) * per_page
    qtable = quote_identifier(options.table)
    order_sql = options.order.present? ? "ORDER BY #{quote_identifier(options.order)}" : ''

    with_client do |client|
      cols = client.query("SELECT * FROM #{qtable} LIMIT 0", as: :array).fields
      where, binds = preview_where(options, cols)
      total = count_rows(client, qtable, where, binds)
      stmt = client.prepare("SELECT * FROM #{qtable}#{where} #{order_sql} LIMIT ? OFFSET ?")
      result = stmt.execute(*binds, per_page, offset, as: :array)
      Result.new(rows: result.to_a, columns: result.fields, row_count: total, elapsed_ms: nil)
    end
  end

  def count_rows(client, qtable, where, binds)
    sql = "SELECT COUNT(*) AS c FROM #{qtable}#{where}"
    row = binds.any? ? client.prepare(sql).execute(*binds, as: :hash).first : client.query(sql, as: :hash).first
    row['c'].to_i
  end

  # WHERE del preview: filtros exactos por columna + búsqueda de texto (LIKE) en todas las
  # columnas. Valores por bind (?). Identificadores citados. Sólo columnas existentes.
  def preview_where(options, cols)
    binds = []
    clauses = preview_filter_pairs(options, cols).map do |col, values|
      placeholders = values.map do |v|
        binds << v
        '?'
      end
      "#{quote_identifier(col)} IN (#{placeholders.join(', ')})"
    end
    if options.search.present?
      like = "%#{options.search}%"
      ors = cols.map do |c|
        binds << like
        "CAST(#{quote_identifier(c)} AS CHAR) LIKE ?"
      end
      clauses << "(#{ors.join(' OR ')})"
    end
    [clauses.any? ? " WHERE #{clauses.join(' AND ')}" : '', binds]
  end

  def execute(sql, binds: [], row_limit: nil)
    cap = row_cap(row_limit)
    wrapped = "SELECT * FROM (#{subquery_body(sql)}) AS jabvox_sub LIMIT #{cap}"
    started = monotonic_ms
    with_client do |client|
      result = if binds.any?
                 client.prepare(wrapped).execute(*binds, as: :array)
               else
                 client.query(wrapped, as: :array)
               end
      rows = result.to_a
      Result.new(rows: rows, columns: result.fields, row_count: rows.size, elapsed_ms: monotonic_ms - started)
    end
  end

  protected

  def identifier_quote
    '`'
  end

  def probe(client)
    client.query('SELECT 1')
  end

  def with_client
    client = Mysql2::Client.new(connection_params)
    # MySQL 5.7.8+ uses max_execution_time (ms); MariaDB uses max_statement_time (s). Try both.
    safe_session(client)
    client.query('START TRANSACTION READ ONLY')
    result = yield client
    client.query('COMMIT')
    result
  rescue Mysql2::Error => e
    raise ConnectionError, e.message
  ensure
    client&.close
  end

  private

  def safe_session(client)
    client.query('SET SESSION TRANSACTION READ ONLY')
    client.query("SET SESSION max_execution_time = #{timeout_ms}")
  rescue Mysql2::Error
    # MariaDB: max_execution_time is unknown; fall back to max_statement_time (seconds).
    begin
      client.query("SET SESSION max_statement_time = #{(timeout_ms / 1000.0).ceil}")
    rescue Mysql2::Error
      nil # neither available; the connect/read timeout still applies
    end
  end

  def connection_params
    {
      host: data_source.host_jabvox,
      port: data_source.effective_port,
      username: data_source.username_jabvox,
      password: data_source.password_jabvox,
      database: data_source.database_jabvox,
      # Read as utf8mb4 so accented letters and ñ (stored as UTF-8 in the source)
      # arrive intact instead of being mangled by a mismatched default charset.
      # Rows already corrupted at the origin (a literal "?" byte on disk) cannot
      # be recovered — that is source data loss, not a read problem.
      encoding: 'utf8mb4',
      connect_timeout: (timeout_ms / 1000.0).ceil,
      read_timeout: (timeout_ms / 1000.0).ceil,
      reconnect: false
    }.compact
  end

  def build_relation(rel, meta)
    key = rel['TABLE_NAME']
    {
      name: key,
      type: rel['TABLE_TYPE'] == 'VIEW' ? :view : :table,
      columns: (meta[:columns][key] || []).map { |col| build_column(col, key, meta) }
    }
  end

  def build_column(col, table_key, meta)
    {
      name: col['COLUMN_NAME'],
      type: col['DATA_TYPE'],
      nullable: col['IS_NULLABLE'] == 'YES',
      length: col['CHARACTER_MAXIMUM_LENGTH'],
      primary_key: col['COLUMN_KEY'] == 'PRI',
      foreign_key: meta[:fks].dig(table_key, col['COLUMN_NAME'])
    }
  end

  def fetch_relations(client, db)
    stmt = client.prepare(
      'SELECT TABLE_NAME, TABLE_TYPE FROM information_schema.TABLES WHERE TABLE_SCHEMA = ? ORDER BY TABLE_NAME'
    )
    stmt.execute(db, as: :hash).to_a
  end

  def fetch_columns(client, db)
    stmt = client.prepare(<<~SQL.squish)
      SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, IS_NULLABLE, CHARACTER_MAXIMUM_LENGTH, COLUMN_KEY
      FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = ? ORDER BY TABLE_NAME, ORDINAL_POSITION
    SQL
    stmt.execute(db, as: :hash).to_a.group_by { |r| r['TABLE_NAME'] }
  end

  def fetch_foreign_keys(client, db)
    stmt = client.prepare(<<~SQL.squish)
      SELECT TABLE_NAME, COLUMN_NAME, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME
      FROM information_schema.KEY_COLUMN_USAGE
      WHERE TABLE_SCHEMA = ? AND REFERENCED_TABLE_NAME IS NOT NULL
    SQL
    stmt.execute(db, as: :hash).to_a.each_with_object({}) do |r, acc|
      (acc[r['TABLE_NAME']] ||= {})[r['COLUMN_NAME']] =
        { table: r['REFERENCED_TABLE_NAME'], column: r['REFERENCED_COLUMN_NAME'] }
    end
  end
end
