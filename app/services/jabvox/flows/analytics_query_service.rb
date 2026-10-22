# frozen_string_literal: true

# Ejecuta una consulta de SOLO LECTURA contra una fuente de datos externa de
# Analytics (jabvox_analytics_data_sources) para el nodo de flujo
# `integration.analytics_query`, y devuelve las filas como un array de hashes.
#
# Reutiliza íntegra la infraestructura segura de Analytics:
#   - HostGuardService  -> anti-SSRF (resuelve DNS, bloquea rangos privados/metadata).
#   - SqlValidatorService -> SELECT read-only (denylist keywords/funciones + AST pg_query).
#   - AdapterFactory/BaseAdapter#execute -> conexión short-lived, read-only a nivel de
#     servidor (BEGIN READ ONLY), statement_timeout y LIMIT forzado, cierre garantizado.
#
# Alcance: se autoriza por `account_id` (la fuente debe pertenecer a la cuenta del
# run) + el enforcement read-only del adapter. NO usa el RBAC per-user de Analytics,
# porque un flujo disparado por horario no tiene usuario (el Context solo lleva
# account_id). El aislamiento multi-tenant lo da el scope por cuenta.
#
# Siempre trae datos FRESCOS: no cachea (un flujo de las 9am debe ver lo de hoy).
class Jabvox::Flows::AnalyticsQueryService
  class QueryError < StandardError; end

  Result = Struct.new(:rows, :columns, :row_count, :elapsed_ms, keyword_init: true)

  # Operadores permitidos en el modo "builder" (mapeo de columnas/filtros).
  # Allowlist FIJA de operadores del modo "builder". Un operador que no esté aquí se
  # descarta: el usuario nunca inyecta un operador arbitrario en el WHERE.
  OPERATORS = { 'eq' => '=', 'neq' => '<>', 'gt' => '>', 'gte' => '>=',
                'lt' => '<', 'lte' => '<=', 'like' => 'LIKE' }.freeze

  def initialize(account_id:, data_source_id:, limit: nil)
    @account_id = account_id
    @data_source_id = data_source_id
    @limit = limit
  end

  # Modo SQL libre. `params` son los valores de los marcadores {{nombre}} del SQL.
  def run_sql(sql, params: {})
    source = resolve_source!
    guard_host!(source)
    validate_sql!(sql)
    bound_sql, binds = bind_placeholders(source, sql, params)
    execute(source, bound_sql, binds)
  end

  # Modo builder: tabla + columnas + filtros + orden. Genera el SELECT de forma
  # segura (identificadores citados por el adapter, valores escapados).
  def run_builder(table:, columns: nil, filters: [], order_by: nil, order_dir: 'ASC')
    source = resolve_source!
    guard_host!(source)
    adapter = adapter_for(source)
    sql = build_select(adapter, { table: table, columns: columns, filters: filters,
                                  order_by: order_by, order_dir: order_dir })
    execute(source, sql, [])
  end

  private

  # La fuente debe existir, pertenecer a la cuenta del run y estar probada (ok).
  def resolve_source!
    source = JabvoxAnalyticsDataSource.where(account_id: @account_id).find_by(id: @data_source_id)
    raise QueryError, 'La fuente de datos no existe en esta cuenta.' if source.nil?

    unless source.status_jabvox == 'ok'
      raise QueryError,
            "La fuente de datos «#{source.name_jabvox}» no está conectada (estado: #{source.status_jabvox})."
    end

    source
  end

  def adapter_for(source)
    Jabvox::Analytics::AdapterFactory.for(source)
  end

  # Anti-SSRF antes de abrir conexión (el adapter no lo hace por sí mismo).
  def guard_host!(source)
    return if source.engine_jabvox == 'sqlite'

    result = Jabvox::Analytics::HostGuardService.new(
      host: source.host_jabvox, port: source.effective_port,
      allow_private: source.allow_private_network_jabvox,
      allowed_ports: (Jabvox::Analytics::HostGuardService::DEFAULT_ALLOWED_PORTS + [source.effective_port.to_i]).uniq
    ).call
    raise QueryError, result.reason unless result.allowed?
  end

  def validate_sql!(sql)
    raise QueryError, 'Escribe la consulta SQL (SELECT) a ejecutar.' if sql.to_s.strip.blank?

    validation = Jabvox::Analytics::SqlValidatorService.new(sql).call
    raise QueryError, validation.message unless validation.valid?
  end

  # Marcadores {{nombre}} -> binds del dialecto, para que un valor no altere la forma
  # de la consulta (misma protección que QueryExecutionService, sin caché).
  PLACEHOLDER_RE = /\{\{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}/
  def bind_placeholders(source, sql, params)
    adapter = adapter_for(source)
    values = (params || {}).transform_keys(&:to_s)
    binds = []
    bound = sql.gsub(PLACEHOLDER_RE) do
      name = Regexp.last_match(1)
      next Regexp.last_match(0) unless values.key?(name)

      binds << values[name]
      adapter.dialect == :postgres ? "$#{binds.size}" : '?'
    end
    [bound, binds]
  end

  # SELECT seguro del modo builder. Identificadores citados por el adapter; valores
  # de filtro escapados (los adapters no exponen binds de servidor para esta ruta).
  def build_select(adapter, spec)
    table = spec[:table]
    raise QueryError, 'Elige la tabla a consultar.' if table.to_s.strip.blank?

    cols = Array(spec[:columns]).map(&:to_s).reject(&:blank?)
    select = cols.any? ? cols.map { |c| adapter.quote_identifier(c) }.join(', ') : '*'
    sql = "SELECT #{select} FROM #{adapter.quote_identifier(table.to_s)}"
    where = build_where(adapter, spec[:filters])
    sql += " WHERE #{where}" if where.present?
    sql += build_order(adapter, spec[:order_by], spec[:order_dir])
    sql
  end

  def build_where(adapter, filters)
    Array(filters).filter_map do |f|
      f = f.with_indifferent_access
      op = OPERATORS[f[:operator].to_s]
      next if op.nil? || f[:column].to_s.blank?

      "#{adapter.quote_identifier(f[:column].to_s)} #{op} #{quote_literal(f[:value])}"
    end.join(' AND ')
  end

  def build_order(adapter, order_by, order_dir)
    return '' if order_by.to_s.strip.blank?

    dir = order_dir.to_s.upcase == 'DESC' ? 'DESC' : 'ASC'
    " ORDER BY #{adapter.quote_identifier(order_by.to_s)} #{dir}"
  end

  def quote_literal(value)
    return value.to_s if value.is_a?(Numeric)

    "'#{value.to_s.gsub("'", "''")}'"
  end

  # Ejecuta con tope de filas (el menor entre lo pedido y el max_rows de la fuente),
  # fresco, con cierre de conexión garantizado por el adapter.
  def execute(source, sql, binds)
    adapter = adapter_for(source)
    cap = row_cap(source)
    result = adapter.execute(sql, binds: binds, row_limit: cap)
    rows = result.rows.map { |row| result.columns.zip(row).to_h }
    Result.new(rows: rows, columns: result.columns, row_count: result.row_count, elapsed_ms: result.elapsed_ms)
  rescue Jabvox::Analytics::Adapters::BaseAdapter::ConnectionError => e
    raise QueryError, e.message
  end

  def row_cap(source)
    source_cap = source.max_rows_jabvox.to_i
    source_cap = 1000 if source_cap <= 0
    requested = @limit.to_i
    requested.positive? ? [requested, source_cap].min : source_cap
  end
end
