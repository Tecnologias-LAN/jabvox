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

  def run_custom_sql(sql)
    validation = Jabvox::Analytics::SqlValidatorService.new(sql).call
    raise RejectedError, validation.message unless validation.valid?

    cached_execute(cache_parts: ['custom', sql], sql: sql, binds: [])
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

  private

  def cached_execute(cache_parts:, sql:, binds:)
    cache = Jabvox::Analytics::CacheService.new(account: @data_source.account, data_source: @data_source, user: @user)
    cached = cache.read(cache.key_for(cache_parts))
    return Outcome.new(**cached, cached: true) if cached

    result = @adapter.execute(sql, binds: binds)
    outcome = normalize(result, cached: false)
    cache.write(cache.key_for(cache_parts), outcome.to_h.except(:cached), @ttl)
    outcome
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
end
