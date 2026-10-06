# Orchestrates running a query against a data source: cache lookup -> (validate, for custom
# SQL) -> adapter.execute (read-only) -> cache store. Returns a normalized hash.
#
#   svc = Jabvox::Analytics::QueryExecutionService.new(data_source: ds, user: u)
#   svc.run_visual(spec)            # builds SQL from the spec, executes
#   svc.run_custom_sql(sql)         # validates read-only, executes
#   svc.preview(table:, ...)        # paginated table preview (not cached)
class Jabvox::Analytics::QueryExecutionService
  RejectedError = Class.new(StandardError)

  Outcome = Struct.new(:rows, :columns, :row_count, :elapsed_ms, :cached, keyword_init: true) do
    def to_h
      { rows: rows, columns: columns, row_count: row_count, elapsed_ms: elapsed_ms, cached: cached }
    end
  end

  def initialize(data_source:, user: nil, ttl_seconds: nil)
    @data_source = data_source
    @user = user
    @ttl = ttl_seconds || 300
    @adapter = Jabvox::Analytics::AdapterFactory.for(@data_source)
  end

  def run_visual(spec)
    sql, binds = Jabvox::Analytics::QueryBuilderService.new(@adapter, spec).build
    cached_execute(cache_parts: ['visual', spec], sql: sql, binds: binds)
  end

  # Compila un spec visual a SQL legible (con los valores ya insertados), SIN ejecutarlo.
  # Se usa para la conversión visual→SQL del editor de widgets. No toca la base externa.
  def compile_sql(spec)
    sql, binds = Jabvox::Analytics::QueryBuilderService.new(@adapter, spec).build
    binds.each do |value|
      literal = value.is_a?(Numeric) ? value.to_s : "'#{value.to_s.gsub("'", "''")}'"
      sql = sql.sub(/\$\d+|\?/, literal)
    end
    sql
  end

  # `params` son los valores de los marcadores `{{nombre}}` del SQL (p.ej. el ciclo que el
  # usuario elige en la barra de filtros del tablero). El marcador se sustituye por un
  # placeholder y el valor viaja como bind: el SQL ejecutado no cambia de forma con el
  # filtro, así que un valor malicioso no puede alterar la consulta.
  def run_custom_sql(sql, params: {})
    validation = Jabvox::Analytics::SqlValidatorService.new(sql).call
    raise RejectedError, validation.message unless validation.valid?

    bound_sql, binds = bind_placeholders(sql, params)
    cached_execute(cache_parts: ['custom', bound_sql, binds], sql: bound_sql, binds: binds)
  end

  PLACEHOLDER_RE = /\{\{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}/

  # Un marcador sin valor se deja tal cual: así una consulta a medio configurar falla en la
  # base con un error visible, en vez de ejecutarse en silencio sin el filtro y mostrar
  # cifras de todos los ciclos como si fueran del ciclo elegido.
  def bind_placeholders(sql, params)
    values = (params || {}).transform_keys(&:to_s)
    binds = []
    bound = sql.gsub(PLACEHOLDER_RE) do
      name = Regexp.last_match(1)
      next Regexp.last_match(0) unless values.key?(name)

      binds << values[name]
      @adapter.dialect == :postgres ? "$#{binds.size}" : '?'
    end
    [bound, binds]
  end

  # Not cached: preview is interactive/paginated. Accepts a hash of preview options
  # (the REST `sort` param maps to PreviewOptions#order).
  def preview(opts)
    o = opts.symbolize_keys
    options = Jabvox::Analytics::Adapters::BaseAdapter::PreviewOptions.new(
      table: o[:table], page: o[:page], per_page: o[:per_page],
      order: o[:sort], search: o[:search], filters: o[:filters]
    )
    normalize(@adapter.preview_table(options), cached: false)
  end

  # Valores distintos de una columna, para los filtros seleccionables del visor de datos.
  # La tabla y la columna se citan con el adapter (identificadores), la búsqueda va por bind.
  # Sólo lectura (SELECT DISTINCT). Cacheado breve porque se pide al abrir cada dropdown.
  def distinct_values(table:, column:, search: nil, limit: 200)
    limit = limit.to_i.clamp(1, 1000)
    sql, binds = build_distinct(table, column, search, limit)
    key = with_ar { cache.key_for(['distinct', table, column, search, limit]) }
    cached = with_ar { cache.read(key) }
    return cached if cached

    result = @adapter.execute(sql, binds: binds)
    values = result.rows.map(&:first).reject { |v| v.nil? || v.to_s.strip.empty? }
    payload = { values: values, truncated: values.size >= limit }
    with_ar { cache.write(key, payload, 120) }
    payload
  end

  private

  # Escalabilidad: la consulta a la base externa (@adapter.execute) puede tardar segundos.
  # NO debe correr mientras se retiene una conexión del pool de ActiveRecord de la app, o
  # bajo concurrencia el pool se agota y hasta las peticiones normales de la app se cuelgan
  # (ConnectionTimeoutError). Por eso los accesos a AR (caché durable) se envuelven en
  # with_connection —que devuelve la conexión al pool al salir— y la ejecución externa
  # ocurre entre medias, sin conexión AR retenida.
  def cached_execute(cache_parts:, sql:, binds:)
    key = with_ar { cache.key_for(cache_parts) }
    cached = with_ar { cache.read(key) }
    return Outcome.new(**cached, cached: true) if cached

    result = @adapter.execute(sql, binds: binds) # I/O externo, sin conexión AR retenida
    outcome = normalize(result, cached: false)
    with_ar { cache.write(key, outcome.to_h.except(:cached), @ttl) }
    outcome
  end

  # La cuenta se resuelve una sola vez (dentro de un checkout AR) y se memoiza, para no
  # tocar el pool en cada acceso.
  def cache
    @cache ||= with_ar do
      Jabvox::Analytics::CacheService.new(account: @data_source.account, data_source: @data_source, user: @user)
    end
  end

  # Ejecuta un bloque que usa ActiveRecord garantizando que la conexión vuelva al pool al
  # terminar. Anidado es seguro: with_connection reutiliza la conexión ya tomada.
  def with_ar(&)
    ActiveRecord::Base.connection_pool.with_connection(&)
  end

  def normalize(result, cached:)
    Outcome.new(
      rows: result.rows,
      columns: result.columns,
      row_count: result.row_count,
      elapsed_ms: result.elapsed_ms,
      cached: cached
    )
  end

  def build_distinct(table, column, search, limit)
    qtable = @adapter.quote_identifier(table)
    qcol = @adapter.quote_identifier(column)
    binds = []
    where = ''
    if search.present?
      binds << "%#{search}%"
      where = " WHERE #{qcol} LIKE #{placeholder(1)}"
    end
    [distinct_sql(qtable, qcol, where, limit), binds]
  end

  # SELECT DISTINCT con tope de filas por dialecto (SQL Server usa TOP, el resto LIMIT).
  def distinct_sql(qtable, qcol, where, limit)
    if @adapter.dialect == :sqlserver
      "SELECT DISTINCT TOP (#{limit}) #{qcol} FROM #{qtable}#{where} ORDER BY #{qcol}"
    else
      "SELECT DISTINCT #{qcol} FROM #{qtable}#{where} ORDER BY #{qcol} LIMIT #{limit}"
    end
  end

  def placeholder(index)
    @adapter.dialect == :postgres ? "$#{index}" : '?'
  end
end
