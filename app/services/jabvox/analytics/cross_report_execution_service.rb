# Executes a cross-source report: pulls each participating source separately (each
# through its own adapter / connection, with the host guard and read-only enforced
# per source), then joins the results IN THE APP following the declared relations
# (mapping by a common field). This is what makes it possible to relate data across
# databases on DIFFERENT servers, where native SQL JOINs are impossible.
#
# Join algorithm: a hash join. Sources are joined in dependency order starting from
# the first one; each relation builds a lookup on the right source keyed by the join
# column and merges matching rows (inner) or keeps left rows with nulls (left join).
# Every source is capped (per_source_cap) so nothing pulls an unbounded set into
# memory. The final result is capped to row_limit.
class Jabvox::Analytics::CrossReportExecutionService
  Result = Struct.new(:rows, :columns, :row_count, :truncated, :sources, keyword_init: true)

  class ExecutionError < StandardError; end

  def initialize(report)
    @report = report
    @sources = report.cross_sources.order(:position_jabvox, :id).to_a
    @joins = report.cross_joins.order(:position_jabvox, :id).to_a
  end

  def call
    raise ExecutionError, 'El reporte no tiene fuentes' if @sources.empty?

    pulled = pull_all_sources # { source_id => { columns:, rows: [Hash] } }
    joined = @joins.empty? ? single_source_rows(pulled) : apply_joins(pulled)
    finalize(joined)
  end

  private

  # Pull each source's rows as an array of hashes keyed by "alias.column".
  def pull_all_sources
    @sources.each_with_object({}) do |src, acc|
      acc[src.id] = pull_source(src)
    end
  end

  def pull_source(src)
    adapter = Jabvox::Analytics::AdapterFactory.for(src.data_source)
    guard_source!(src)
    sql = build_source_sql(src)
    result = adapter.execute(sql, row_limit: @report.per_source_cap)
    qualified = result.columns.map { |c| "#{src.alias_jabvox}.#{c}" }
    rows = result.rows.map { |row| qualified.zip(row).to_h }
    { alias: src.alias_jabvox, columns: qualified, rows: rows }
  rescue Jabvox::Analytics::Adapters::BaseAdapter::ConnectionError => e
    raise ExecutionError, "Fuente '#{src.alias_jabvox}': #{e.message}"
  end

  # Validate the source's host before connecting (SSRF/anti-rebinding), unless sqlite.
  def guard_source!(src)
    ds = src.data_source
    return if ds.engine_jabvox == 'sqlite'

    result = Jabvox::Analytics::HostGuardService.new(
      host: ds.host_jabvox, port: ds.effective_port,
      allow_private: ds.allow_private_network_jabvox,
      allowed_ports: (Jabvox::Analytics::HostGuardService::DEFAULT_ALLOWED_PORTS + [ds.effective_port.to_i]).uniq
    ).call
    raise ExecutionError, "Fuente '#{src.alias_jabvox}': #{result.reason}" unless result.allowed?
  end

  # SELECT the chosen columns (or *) from the source's table, applying its filters.
  # Identifiers are quoted by the source's own adapter; filter values are bound.
  def build_source_sql(src)
    adapter = Jabvox::Analytics::AdapterFactory.for(src.data_source)
    cols = src.selected_columns
    select = cols ? cols.map { |c| adapter.quote_identifier(c) }.join(', ') : '*'
    sql = "SELECT #{select} FROM #{adapter.quote_identifier(src.table_jabvox)}"
    where = build_where(src, adapter)
    where.present? ? "#{sql} WHERE #{where}" : sql
  end

  # Builds a safe WHERE from the source's filters. Only a whitelist of operators;
  # values are single-quote-escaped (the adapters don't expose server binds here).
  def build_where(src, adapter)
    clauses = src.normalized_filters.filter_map do |f|
      op = filter_operator(f['operator'])
      next unless op

      col = adapter.quote_identifier(f['column'])
      "#{col} #{op} #{quote_literal(f['value'])}"
    end
    clauses.join(' AND ')
  end

  OPERATORS = { 'eq' => '=', 'neq' => '<>', 'gt' => '>', 'gte' => '>=', 'lt' => '<', 'lte' => '<=' }.freeze
  def filter_operator(operator)
    OPERATORS[operator.to_s]
  end

  def quote_literal(value)
    return value.to_s if value.is_a?(Numeric)

    "'#{value.to_s.gsub("'", "''")}'"
  end

  # No joins declared: just the first source (or a flat union of one). Returns rows
  # as hashes keyed by qualified column.
  def single_source_rows(pulled)
    first = pulled[@sources.first.id]
    { columns: first[:columns], rows: first[:rows] }
  end

  # Apply the declared relations sequentially with a hash join.
  def apply_joins(pulled)
    base = pulled[@sources.first.id]
    acc_rows = base[:rows]
    acc_columns = base[:columns].dup
    joined_ids = [@sources.first.id]

    @joins.each do |j|
      left, right = orient_join(j, joined_ids)
      right_data = pulled[right.id]
      acc_columns |= right_data[:columns]
      acc_rows = hash_join(acc_rows, right_data[:rows], join_key(j, left), join_key(j, right, right: true), j.join_type_jabvox)
      joined_ids |= [right.id]
    end
    { columns: acc_columns, rows: acc_rows }
  end

  # Ensure the already-joined side is treated as "left". If the relation was declared
  # in the opposite order, swap so we always extend the accumulated result.
  def orient_join(join, joined_ids)
    if joined_ids.include?(join.left_source_id)
      [join.left_source, join.right_source]
    else
      [join.right_source, join.left_source]
    end
  end

  # Qualified key ("alias.column") for one side of a relation.
  def join_key(join, source, right: false)
    col = if source.id == join.left_source_id
            join.left_column_jabvox
          else
            join.right_column_jabvox
          end
    _ = right
    "#{source.alias_jabvox}.#{col}"
  end

  # Hash join: index the right rows by their key, then for each left row emit the
  # merged row(s). inner = only matches; left = keep unmatched left rows with the
  # right columns null.
  def hash_join(left_rows, right_rows, left_key, right_key, join_type)
    index = right_rows.group_by { |r| r[right_key] }
    null_right = (right_rows.first&.keys || []).index_with { nil }
    left_rows.flat_map do |lrow|
      merge_left_row(lrow, index[lrow[left_key]], null_right, join_type)
    end
  end

  # One left row → its merged output rows: every match (inner/left), or a single
  # null-padded row when there is no match and the join is a left join, or nothing.
  def merge_left_row(lrow, matches, null_right, join_type)
    if matches.present?
      matches.map { |rrow| lrow.merge(rrow) }
    elsif join_type == 'left'
      [lrow.merge(null_right)]
    else
      []
    end
  end

  # Cap to row_limit, flatten to arrays in a stable column order.
  def finalize(joined)
    columns = joined[:columns]
    all_rows = joined[:rows]
    limit = @report.row_limit_jabvox.to_i
    truncated = all_rows.size > limit
    rows = all_rows.first(limit).map { |h| columns.map { |c| h[c] } }
    Result.new(
      rows: rows, columns: columns, row_count: rows.size, truncated: truncated,
      sources: @sources.map { |s| { alias: s.alias_jabvox, table: s.table_jabvox } }
    )
  end
end
