# Write-only access to an account's external database. Everything is executed with
# PARAMETERIZED statements (pg exec_params / mysql2 prepared statements): table and
# column names come from Jabvox's own schema (quoted), and values are always binds —
# so nothing from user data can be injected. Short-lived connection per operation.
class Jabvox::ExternalExport::WriteAdapter
  ConnectionError = Class.new(StandardError)

  def initialize(target)
    @target = target
    @engine = target.engine_jabvox.to_s
  end

  # { success:, message: } — opens a connection and runs a trivial probe.
  # Runs the SSRF guard first so testing a connection can't be used to probe the
  # internal network or cloud metadata (same protection as every write path).
  def test_connection
    Jabvox::ExternalExport.guard!(@target)
    with_client { |c| probe(c) }
    { success: true, message: 'Conexión exitosa' }
  rescue StandardError => e
    { success: false, message: sanitize(e) }
  end

  # Creates the table if missing, then adds any missing columns (idempotent).
  # `columns` is [{ name:, type: }]; types are a small safe whitelist mapped per engine.
  # `unique_key` (default 'id_jabvox') gets a UNIQUE index so ON CONFLICT / ON
  # DUPLICATE KEY upserts work — without it Postgres rejects ON CONFLICT.
  def ensure_table(table, columns, unique_key: 'id_jabvox')
    with_client do |client|
      exec(client, create_table_sql(table, columns))
      existing = existing_columns(client, table)
      columns.each do |col|
        # Compare using the normalized name (same sanitize+truncate the DDL uses),
        # so idempotency holds for long/special names.
        next if existing.include?(normalized_identifier(col[:name]))

        exec(client, "ALTER TABLE #{qi(table)} ADD COLUMN #{qi(col[:name])} #{sql_type(col[:type])}")
      end
      ensure_unique_index(client, table, unique_key) if unique_key.present?
    end
  end

  # Adds any columns that don't exist yet (opt-in DDL). Never creates the table.
  # Returns the columns that were actually added.
  def add_missing_columns(table, columns)
    added = []
    with_client do |client|
      existing = existing_columns(client, table)
      columns.each do |col|
        next if existing.include?(normalized_identifier(col[:name]))

        exec(client, "ALTER TABLE #{qi(table)} ADD COLUMN #{qi(col[:name])} #{sql_type(col[:type])}")
        added << col[:name]
      end
    end
    added
  end

  # Upserts one row keyed by `conflict_key` (default 'id_jabvox' for create mode;
  # in map mode it's the customer's key column). values is a { column => value }
  # hash whose keys are already-safe column names. Values go as binds.
  def upsert_row(table, values, conflict_key: 'id_jabvox')
    with_client { |client| upsert_row_on(client, table, values, conflict_key: conflict_key) }
  end

  # Opens ONE connection and yields it, so a batch of writes (backfill) reuses a
  # single connection instead of opening one per row. Use with #upsert_row_on.
  def with_connection(&block)
    with_client(&block)
  end

  # Upsert using an already-open client (batch path). Same SQL as #upsert_row.
  def upsert_row_on(client, table, values, conflict_key: 'id_jabvox')
    cols = values.keys
    exec_params(client, upsert_sql(table, cols, conflict_key), values.values_at(*cols))
  end

  # Multi-row upsert on an open client: one INSERT ... VALUES (row),(row),...
  # for the whole batch. Rows are hashes sharing the SAME columns `cols`. This is
  # the backfill fast path — over a remote DB it's ~100x fewer round-trips than
  # row-by-row. Values are always binds (never interpolated).
  def upsert_batch_on(client, table, cols, rows, conflict_key: 'id_jabvox')
    return if rows.empty?

    exec_params(client, batch_upsert_sql(table, cols, rows.size, conflict_key),
                rows.flat_map { |r| cols.map { |c| r[c] } })
  end

  private

  # INSERT with N value tuples: (\$1,\$2),(\$3,\$4)... for pg; (?,?),(?,?)... for mysql.
  def batch_upsert_sql(table, cols, row_count, conflict_key)
    ncols = cols.size
    tuples = Array.new(row_count) do |ri|
      "(#{Array.new(ncols) { |ci| bind(ri * ncols + ci) }.join(', ')})"
    end
    head = "INSERT INTO #{qi(table)} (#{cols.map { |c| qi(c) }.join(', ')}) VALUES #{tuples.join(', ')}"
    if @engine == 'postgresql'
      updates = cols.reject { |c| c == conflict_key }.map { |c| "#{qi(c)} = EXCLUDED.#{qi(c)}" }
      "#{head} ON CONFLICT (#{qi(conflict_key)}) DO UPDATE SET #{updates.join(', ')}"
    else
      updates = cols.reject { |c| c == conflict_key }.map { |c| "#{qi(c)} = VALUES(#{qi(c)})" }
      "#{head} ON DUPLICATE KEY UPDATE #{updates.join(', ')}"
    end
  end

  # ---- SQL builders (identifiers quoted, types whitelisted) ----

  # Idempotently ensures a UNIQUE index on `key_col` so upserts have a conflict
  # target. Postgres: CREATE UNIQUE INDEX IF NOT EXISTS. MySQL/MariaDB: check
  # information_schema first (no IF NOT EXISTS for indexes), then create.
  def ensure_unique_index(client, table, key_col)
    idx = "ux_#{table}_#{key_col}".gsub(/[^a-zA-Z0-9_]/, '')[0, 60]
    if @engine == 'postgresql'
      exec(client, "CREATE UNIQUE INDEX IF NOT EXISTS #{qi(idx)} ON #{qi(table)} (#{qi(key_col)})")
    else
      res = client.prepare(
        'SELECT COUNT(*) FROM information_schema.STATISTICS ' \
        'WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? AND INDEX_NAME = ?'
      ).execute(@target.database_jabvox, table, idx, as: :array).first
      exec(client, "CREATE UNIQUE INDEX #{qi(idx)} ON #{qi(table)} (#{qi(key_col)})") if res.first.to_i.zero?
    end
  rescue StandardError => e
    # A pre-existing duplicate value can make this fail; surface as a connection
    # error so the caller records it, but don't crash the whole schema build.
    raise ConnectionError, "No se pudo crear índice único en #{table}.#{key_col}: #{e.message}"
  end

  def create_table_sql(table, columns)
    defs = columns.map { |c| "#{qi(c[:name])} #{sql_type(c[:type])}" }
    pk = @engine == 'postgresql' ? 'id BIGINT' : 'id BIGINT'
    "CREATE TABLE IF NOT EXISTS #{qi(table)} (#{defs.join(', ')})".tap do |_|
      # id_jabvox uniqueness is enforced via the upsert; a plain table is enough.
      _ = pk
    end
  end

  def upsert_sql(table, cols, conflict_key)
    placeholders = cols.each_index.map { |i| bind(i) }
    if @engine == 'postgresql'
      updates = cols.reject { |c| c == conflict_key }.map { |c| "#{qi(c)} = EXCLUDED.#{qi(c)}" }
      "INSERT INTO #{qi(table)} (#{cols.map { |c| qi(c) }.join(', ')}) " \
        "VALUES (#{placeholders.join(', ')}) " \
        "ON CONFLICT (#{qi(conflict_key)}) DO UPDATE SET #{updates.join(', ')}"
    else
      updates = cols.reject { |c| c == conflict_key }.map { |c| "#{qi(c)} = VALUES(#{qi(c)})" }
      "INSERT INTO #{qi(table)} (#{cols.map { |c| qi(c) }.join(', ')}) " \
        "VALUES (#{placeholders.join(', ')}) " \
        "ON DUPLICATE KEY UPDATE #{updates.join(', ')}"
    end
  end

  # Bind placeholder per engine: $1.. for pg, ? for mysql.
  def bind(index)
    @engine == 'postgresql' ? "$#{index + 1}" : '?'
  end

  # Small whitelist of storage types (never derived from external input).
  def sql_type(type)
    case type.to_s
    when 'integer', 'bigint' then 'BIGINT'
    when 'float', 'decimal' then 'DOUBLE PRECISION'
    when 'boolean' then @engine == 'postgresql' ? 'BOOLEAN' : 'TINYINT(1)'
    when 'datetime', 'date', 'time' then @engine == 'postgresql' ? 'TIMESTAMP' : 'DATETIME'
    when 'jsonb', 'json' then @engine == 'postgresql' ? 'JSONB' : 'JSON'
    else @engine == 'postgresql' ? 'TEXT' : 'LONGTEXT'
    end
  end

  # ---- Identifier quoting (mirrors the analytics adapters) ----
  # Strips everything but [a-zA-Z0-9_] (blocks SQL injection via identifiers) and
  # truncates to 63 bytes — Postgres/MySQL silently truncate longer identifiers,
  # which would make a CREATE and a later INSERT disagree on the column name. We
  # truncate consistently here so DDL and DML always use the same name.
  MAX_IDENTIFIER_LENGTH = 63

  # The exact identifier that will land in the DB: only [a-zA-Z0-9_], truncated to
  # 63 bytes. Single source of truth so quoting and existence checks agree.
  def normalized_identifier(name)
    name.to_s.gsub(/[^a-zA-Z0-9_]/, '')[0, MAX_IDENTIFIER_LENGTH]
  end

  def qi(name)
    q = @engine == 'mysql' || @engine == 'mariadb' ? '`' : '"'
    "#{q}#{normalized_identifier(name)}#{q}"
  end

  # ---- Connection + execution per engine ----
  # Runs the SSRF guard and connects to a VALIDATED IP (not the raw hostname), so
  # DNS rebinding between the check and the connect can't redirect us to an
  # internal address. The hostname is still passed for TLS certificate/SNI.
  def with_client
    validated_ips = Jabvox::ExternalExport.guard!(@target)
    safe_ip = validated_ips.first
    case @engine
    when 'postgresql' then with_pg(safe_ip) { |c| yield c }
    when 'mysql', 'mariadb' then with_mysql(safe_ip) { |c| yield c }
    else raise ConnectionError, "Motor no soportado: #{@engine}"
    end
  end

  def with_pg(safe_ip)
    require 'pg'
    params = {
      host: @target.host_jabvox, port: @target.effective_port,
      user: @target.username_jabvox, password: @target.password_jabvox,
      dbname: @target.database_jabvox, connect_timeout: timeout_s,
      sslmode: pg_sslmode
    }
    # hostaddr pins the connection to the already-validated IP while host keeps
    # SNI/cert verification working — closes the DNS-rebinding gap.
    params[:hostaddr] = safe_ip if safe_ip.present?
    conn = PG.connect(**params)
    # Cap server-side statement time so a remote lock can't hang the worker.
    conn.exec("SET statement_timeout = #{timeout_s * 1000}") rescue nil
    yield conn
  rescue PG::Error => e
    raise ConnectionError, e.message
  ensure
    conn&.close
  end

  def with_mysql(safe_ip)
    require 'mysql2'
    client = Mysql2::Client.new(
      host: safe_ip.presence || @target.host_jabvox, port: @target.effective_port,
      username: @target.username_jabvox, password: @target.password_jabvox,
      database: @target.database_jabvox, connect_timeout: timeout_s,
      write_timeout: timeout_s, read_timeout: timeout_s, reconnect: false,
      **mysql_ssl_opts
    )
    yield client
  rescue Mysql2::Error => e
    raise ConnectionError, e.message
  ensure
    client&.close
  end

  # PostgreSQL sslmode: default to 'require' (encrypted) instead of 'prefer'
  # (which silently accepts plaintext). Honors an explicit stronger/weaker choice.
  def pg_sslmode
    @target.ssl_mode_jabvox.presence || 'require'
  end

  # MySQL SSL: map the target's ssl mode to mysql2 flags so credentials/data are
  # encrypted in transit. 'disable' opts out explicitly; anything else requires SSL.
  def mysql_ssl_opts
    mode = @target.ssl_mode_jabvox.to_s
    return {} if mode == 'disable'

    { ssl_mode: :required }
  end

  def exec(client, sql)
    @engine == 'postgresql' ? client.exec(sql) : client.query(sql)
  end

  def exec_params(client, sql, binds)
    if @engine == 'postgresql'
      client.exec_params(sql, binds.map { |v| serialize(v) })
    else
      client.prepare(sql).execute(*binds.map { |v| serialize(v) })
    end
  end

  # Ruby values -> DB-safe scalars (hashes/arrays as JSON strings).
  def serialize(value)
    case value
    when Hash, Array then value.to_json
    when Time, DateTime then value.utc.strftime('%Y-%m-%d %H:%M:%S')
    else value
    end
  end

  def existing_columns(client, table)
    if @engine == 'postgresql'
      res = client.exec_params(
        'SELECT column_name FROM information_schema.columns WHERE table_name = $1', [table]
      )
      res.column_values(0)
    else
      stmt = client.prepare(
        'SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?'
      )
      stmt.execute(@target.database_jabvox, table, as: :array).map(&:first)
    end
  rescue StandardError
    []
  end

  def probe(client)
    exec(client, 'SELECT 1')
  end

  def timeout_s
    [(@target.query_timeout_ms_jabvox.to_i / 1000.0).ceil, 1].max
  end

  def sanitize(error)
    Rails.logger.error("[ExternalExport::Write] #{error.class}: #{error.message}")
    'No se pudo conectar o escribir en la base de datos externa'
  end
end
