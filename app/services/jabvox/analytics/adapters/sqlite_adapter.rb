require 'sqlite3'

# SQLite adapter. Opens the database file with a read-only handle (readonly: true), so the
# driver itself rejects writes. The file path is validated by the connection service
# (no traversal, must be under an allowlisted directory) before this adapter is used.
class Jabvox::Analytics::Adapters::SqliteAdapter < Jabvox::Analytics::Adapters::BaseAdapter
  def dialect
    :sqlite
  end

  def schema_introspection
    with_client do |db|
      relations(db).map { |rel| build_relation(db, rel) }
    end
  end

  def preview_table(options)
    per_page = row_cap(options.per_page)
    offset = ([options.page.to_i, 1].max - 1) * per_page
    qtable = quote_identifier(options.table)
    order_sql = options.order.present? ? "ORDER BY #{quote_identifier(options.order)}" : ''

    with_client do |db|
      cols = db.execute2("SELECT * FROM #{qtable} LIMIT 0").first
      where, binds = preview_where(options, cols)
      total = db.get_first_value("SELECT COUNT(*) FROM #{qtable}#{where}", *binds).to_i
      rows = db.execute2("SELECT * FROM #{qtable}#{where} #{order_sql} LIMIT ? OFFSET ?", *binds, per_page, offset)
      columns = rows.shift
      Result.new(rows: rows, columns: columns, row_count: total, elapsed_ms: nil)
    end
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
        "CAST(#{quote_identifier(c)} AS TEXT) LIKE ?"
      end
      clauses << "(#{ors.join(' OR ')})"
    end
    [clauses.any? ? " WHERE #{clauses.join(' AND ')}" : '', binds]
  end

  def execute(sql, binds: [], row_limit: nil)
    cap = row_cap(row_limit)
    wrapped = "SELECT * FROM (#{subquery_body(sql)}) AS jabvox_sub LIMIT #{cap}"
    started = monotonic_ms
    with_client do |db|
      rows = db.execute2(wrapped, *binds)
      columns = rows.shift
      Result.new(rows: rows, columns: columns, row_count: rows.size, elapsed_ms: monotonic_ms - started)
    end
  end

  protected

  def probe(db)
    db.get_first_value('SELECT 1')
  end

  def with_client
    db = SQLite3::Database.new(data_source.sqlite_path_jabvox, readonly: true)
    db.busy_timeout = timeout_ms
    yield db
  rescue SQLite3::Exception => e
    raise ConnectionError, e.message
  ensure
    db&.close
  end

  private

  def build_relation(db, rel)
    cols = db.execute2("PRAGMA table_info(#{quote_identifier(rel['name'])})")
    header = cols.shift
    fks = foreign_keys(db, rel['name'])
    {
      name: rel['name'],
      type: rel['type'] == 'view' ? :view : :table,
      columns: cols.map { |row| build_column(header.zip(row).to_h, fks) }
    }
  end

  def build_column(col, fks)
    {
      name: col['name'],
      type: col['type'],
      nullable: col['notnull'].to_i.zero?,
      length: nil,
      primary_key: col['pk'].to_i.positive?,
      foreign_key: fks[col['name']]
    }
  end

  def relations(db)
    rows = db.execute2("SELECT name, type FROM sqlite_master WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%' ORDER BY name")
    header = rows.shift
    rows.map { |row| header.zip(row).to_h }
  end

  def foreign_keys(db, table)
    rows = db.execute2("PRAGMA foreign_key_list(#{quote_identifier(table)})")
    header = rows.shift
    rows.each_with_object({}) do |row, acc|
      fk = header.zip(row).to_h
      acc[fk['from']] = { table: fk['table'], column: fk['to'] }
    end
  end
end
