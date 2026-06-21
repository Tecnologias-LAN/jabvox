require 'pg_query'

# Validates that custom SQL is strictly read-only, with defense in depth. This is the
# application-level gate; the adapter's read-only DB transaction (Layer A) is the final
# authoritative backstop.
#
#   result = Jabvox::Analytics::SqlValidatorService.new(sql).call
#   result.valid? ; result.message
#
# Order: strip comments -> Layer C (denylist) -> Layer B (pg_query AST) -> ok.
class Jabvox::Analytics::SqlValidatorService
  Result = Struct.new(:valid, :message, keyword_init: true) do
    def valid?
      valid
    end
  end

  # Layer C: forbidden top-level keywords (whole-word).
  FORBIDDEN = %w[
    insert update delete drop truncate alter create grant revoke replace
    merge call do vacuum analyze reindex cluster comment lock copy
    attach detach pragma into
  ].freeze

  # Functions that can read files / sleep / reach out, blocked even inside a SELECT.
  FORBIDDEN_FUNCTIONS = %w[
    pg_read_file pg_read_binary_file pg_ls_dir pg_sleep pg_stat_file
    dblink dblink_connect lo_import lo_export copy_from copy_to
    load_file set_config current_setting benchmark sleep
  ].freeze

  def initialize(sql)
    @raw = sql.to_s
  end

  def call
    return invalid('La consulta está vacía') if @raw.strip.empty?

    sql = strip_comments(@raw)
    return invalid('No se permiten múltiples sentencias') if multiple_statements?(sql)

    denied = denylisted_keyword(sql)
    return invalid("Palabra no permitida: #{denied.upcase}") if denied

    fn = denylisted_function(sql)
    return invalid("Función no permitida: #{fn}") if fn

    ast_error = validate_with_parser(sql)
    return invalid(ast_error) if ast_error

    Result.new(valid: true, message: 'La consulta es de solo lectura')
  end

  private

  def invalid(message)
    Result.new(valid: false, message: message)
  end

  # Remove -- line comments and /* */ block comments so they can't smuggle keywords.
  def strip_comments(sql)
    sql.gsub(%r{/\*.*?\*/}m, ' ').gsub(/--[^\n]*/, ' ').strip
  end

  def multiple_statements?(sql)
    # Allow a single optional trailing semicolon; anything before the end is multiple.
    sql.sub(/;\s*\z/, '').include?(';')
  end

  def denylisted_keyword(sql)
    normalized = " #{sql.downcase.gsub(/\s+/, ' ')} "
    FORBIDDEN.find { |kw| normalized.match?(/[\s(]#{Regexp.escape(kw)}[\s(]/) }
  end

  def denylisted_function(sql)
    lower = sql.downcase
    FORBIDDEN_FUNCTIONS.find { |fn| lower.match?(/\b#{Regexp.escape(fn)}\s*\(/) }
  end

  # Layer B: parse with the real Postgres grammar and require a single SELECT (or CTE-SELECT)
  # with no data-modifying CTEs. Best coverage for Postgres; still a strong shape check for
  # MySQL/SQLite SELECT subset (Layers A+C carry the guarantee there).
  def validate_with_parser(sql)
    parsed = PgQuery.parse(sql)
    stmts = parsed.tree.stmts
    return 'Solo se permite una sentencia' unless stmts.size == 1

    raw = stmts.first.stmt
    select = raw.select_stmt
    return 'Solo se permiten consultas SELECT' if select.nil?

    return 'No se permiten CTE que modifican datos' if modifying_cte?(select)

    nil
  rescue PgQuery::ParseError
    # Not parseable as Postgres (e.g. MySQL/SQLite dialect). Fall back to Layers A+C, which
    # already passed; do not hard-fail valid non-PG SELECTs.
    nil
  end

  def modifying_cte?(select)
    with_clause = select.with_clause
    return false if with_clause.nil?

    with_clause.ctes.any? do |cte|
      stmt = cte.cte_expr.ctequery
      stmt.select_stmt.nil?
    end
  rescue StandardError
    false
  end
end
