# Abstract base for external-database adapters. Subclasses talk to a specific engine
# (PostgreSQL, MySQL/MariaDB, SQLite) using a SHORT-LIVED native client that is fully
# isolated from the app's own ActiveRecord connection pool.
#
# Every caller (connection test, introspection, data preview, query/SQL execution)
# uses ONLY this interface, so adding a new engine later is a new subclass + a line in
# AdapterFactory — no caller changes.
#
# Read-only is enforced per engine at the DB-session level (see #with_client overrides),
# which is the authoritative backstop even if SQL validation upstream is bypassed.
class Jabvox::Analytics::Adapters::BaseAdapter
  Result = Struct.new(:rows, :columns, :row_count, :elapsed_ms, keyword_init: true)

  # Options for a paginated table preview. Bundling these keeps the adapter contract to a
  # single argument and lets future filters (search/filters) ride along without churn.
  # (`order` rather than `sort` to avoid overriding Struct#sort.)
  PreviewOptions = Struct.new(:table, :page, :per_page, :order, :search, :filters, keyword_init: true) do
    def initialize(table:, page: nil, per_page: nil, order: nil, search: nil, filters: nil)
      super(table: table, page: page || 1, per_page: per_page || 100, order: order, search: search, filters: filters)
    end
  end

  ConnectionError = Class.new(StandardError)

  def initialize(data_source)
    @data_source = data_source
  end

  # --- Public contract (subclasses implement the protected primitives) ---

  # { success:, latency_ms:, message: } with a sanitized message.
  def test_connection
    started = monotonic_ms
    with_client do |client|
      probe(client)
    end
    { success: true, latency_ms: (monotonic_ms - started), message: 'Conexión exitosa' }
  rescue StandardError => e
    log_error('test_connection', e)
    { success: false, latency_ms: nil, message: sanitize_error(e) }
  end

  # [{ name:, type: :table|:view, columns: [{ name:, type:, nullable:, primary_key:, foreign_key:, length: }] }]
  def schema_introspection
    raise NotImplementedError
  end

  # Paginated/sorted/filtered preview of one table. Takes a PreviewOptions. Returns a Result.
  def preview_table(_options)
    raise NotImplementedError
  end

  # Runs already-validated read-only SQL. Always enforces a row cap. Returns a Result.
  def execute(_sql, binds: [], row_limit: nil)
    raise NotImplementedError
  end

  def dialect
    raise NotImplementedError
  end

  # Quote an identifier (table/column) for safe interpolation. Subclasses override the char.
  def quote_identifier(name)
    cleaned = name.to_s.gsub(/[^a-zA-Z0-9_.]/, '')
    cleaned.split('.').map { |part| "#{identifier_quote}#{part}#{identifier_quote}" }.join('.')
  end

  protected

  attr_reader :data_source

  def identifier_quote
    '"'
  end

  # Filtros de preview normalizados como pares [columna, valores], donde `valores` es SIEMPRE
  # un array (uno o varios). Permite multi-selección por columna (IN (...)). Descarta vacíos y
  # columnas que no existen en la tabla (defensa: la columna nunca se interpola sin estar en
  # `cols`).
  #
  # Acepta las tres formas en que el valor puede llegar según cómo se serialice el array en la
  # query string:
  #   { col => 20 }                 (valor único)
  #   { col => [20, 30] }           (filters[col][]=20&filters[col][]=30)
  #   { col => { '0'=>20,'1'=>30 } } (filters[col][0]=20&filters[col][1]=30 → Rails lo hace Hash)
  def preview_filter_pairs(options, cols)
    filters = options.filters
    filters = filters.to_unsafe_h if filters.respond_to?(:to_unsafe_h)
    Array(filters).filter_map do |col, raw|
      next if cols.exclude?(col.to_s)

      values = normalize_filter_values(raw)
      next if values.empty?

      [col, values]
    end
  end

  def normalize_filter_values(raw)
    list = raw.is_a?(Hash) ? raw.values : Array(raw)
    list.reject { |v| v.nil? || v.to_s.empty? }
  end

  # La consulta del usuario se envuelve en `SELECT * FROM (...) AS jabvox_sub` para imponer
  # el tope de filas. Un `;` final —que casi todo cliente SQL añade al copiar— dejaba el
  # envoltorio inválido y la base devolvía un error de sintaxis que llegaba al usuario como
  # un "no se pudo completar la operación" sin más pistas.
  #
  # Los comentarios de línea al final también rompen el envoltorio (comentarían el `)` que
  # cierra), así que se recorta hasta dejar solo la sentencia.
  def subquery_body(sql)
    body = sql.to_s.strip
    # Quita comentarios de línea finales que dejarían el paréntesis de cierre comentado.
    body = body.sub(/(\s*--[^\n]*)+\z/, '').rstrip
    body.sub(/;+\s*\z/, '').rstrip
  end

  def row_cap(requested = nil)
    cap = data_source.max_rows_jabvox.to_i
    cap = 1000 if cap <= 0
    requested.present? ? [requested.to_i, cap].min : cap
  end

  def timeout_ms
    ms = data_source.query_timeout_ms_jabvox.to_i
    ms.positive? ? ms : 30_000
  end

  # A trivial query used by test_connection. Subclasses may override.
  def probe(_client)
    raise NotImplementedError
  end

  # Opens a short-lived, read-only native connection, yields it, and always closes it.
  def with_client
    raise NotImplementedError
  end

  # Map low-level driver errors to safe, user-facing Spanish messages — never leak
  # stack traces, hostnames or credentials.
  def sanitize_error(error)
    msg = error.message.to_s
    case msg
    when /password|authentication|access denied|auth/i
      'Error: credenciales inválidas'
    when /could not translate host|getaddrinfo|unknown host|name or service not known|no such host/i
      'Host no encontrado'
    when /timeout|timed out/i
      'Timeout de conexión'
    when /could not connect|connection refused|can't connect/i
      'No se pudo conectar al servidor'
    when /does not exist|unknown database|no such/i
      'La base de datos o tabla no existe'
    else
      'Error de conexión'
    end
  end

  def log_error(operation, error)
    Rails.logger.error "[Analytics::#{self.class.name.demodulize}] #{operation} failed: #{error.class}: #{error.message}"
  end

  def monotonic_ms
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).round
  end
end
