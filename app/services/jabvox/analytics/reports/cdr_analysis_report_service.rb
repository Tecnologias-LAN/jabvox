# frozen_string_literal: true

# Reporte "Análisis CDR" (key: cdr_analysis).
#
# Fuente principal: jabvox_cdr_call_analyses, SIEMPRE acotada a la cuenta vía la
# asociación de ActiveRecord (account.jabvox_cdr_call_analyses). Nunca un scope global.
#
# Columnas relevantes (schema verificado):
#   - status      (string, default "pending", NOT NULL) -> sin enum en BD; el conjunto
#                 real de estados se toma de los datos (incluye "pending").
#   - passed      (boolean, default false, NOT NULL)    -> nunca es NULL; "pass_rate
#                 sobre passed no nulo" NO filtra nada. El denominador correcto del
#                 pass_rate son los registros efectivamente analizados (status = 'analyzed').
#   - final_score (integer, nullable)
#   - pipeline_id (bigint, nullable) -> FK a jabvox_cdr_pipelines
#   - created_at  (datetime) -> usado para el rango de fechas
#
# No hay columna de agente/usuario en esta tabla. El vínculo a agente es indirecto vía
# jabvox_cdr_extension_mappings (extension -> user_id) y NO existe columna `extension`
# en jabvox_cdr_call_analyses, por lo que no es posible cruzar análisis con agente con
# el esquema actual. Esa sección se reporta como no-disponible.
class Jabvox::Analytics::Reports::CdrAnalysisReportService
  STATUS_ANALYZED = 'analyzed'

  def initialize(account:, date_from: nil, date_to: nil, filters: {})
    raise ArgumentError, 'account is required' if account.nil?

    @account = account
    @date_from = date_from
    @date_to = date_to
    @filters = filters || {}
  end

  def call
    {
      summary: build_summary,
      series: build_series,
      by_status: build_by_status,
      by_pipeline: build_by_pipeline,
      by_agent: build_by_agent
    }
  end

  private

  attr_reader :account, :date_from, :date_to, :filters

  # Scope base: análisis de la cuenta acotados por created_at. Nunca global.
  # Filtros adicionales: status y pipeline_id (no hay columna de agente).
  def analyses
    scope = account.jabvox_cdr_call_analyses
    scope = scope.where('jabvox_cdr_call_analyses.created_at >= ?', date_from) if date_from.present?
    scope = scope.where('jabvox_cdr_call_analyses.created_at <= ?', date_to) if date_to.present?
    scope = scope.where(status: filters['status']) if filters['status'].present?
    scope = scope.where(pipeline_id: filters['pipeline_id'].to_i) if filters['pipeline_id'].present?
    scope
  end

  # Registros efectivamente analizados (status = 'analyzed').
  def analyzed_scope
    analyses.where(status: STATUS_ANALYZED)
  end

  def build_summary
    total = analyses.count
    analyzed = analyzed_scope.count
    passed = analyzed_scope.where(passed: true).count

    {
      total_analyses: total,
      analyzed: analyzed,
      passed: passed,
      failed: analyzed - passed,
      # pass_rate calculado sobre los registros analizados (passed nunca es NULL,
      # por eso el denominador real es status = 'analyzed', no "passed no nulo").
      pass_rate: analyzed.zero? ? 0.0 : (passed.to_f / analyzed * 100).round(2),
      avg_final_score: analyzed_scope.where.not(final_score: nil).average(:final_score).to_f.round(2)
    }
  end

  # Serie temporal por día: total de análisis, analizados y aprobados.
  def build_series
    total_by_day = analyses.group('DATE(jabvox_cdr_call_analyses.created_at)').count
    analyzed_by_day = analyzed_scope.group('DATE(jabvox_cdr_call_analyses.created_at)').count
    passed_by_day = analyzed_scope.where(passed: true)
                                  .group('DATE(jabvox_cdr_call_analyses.created_at)').count

    days = (total_by_day.keys + analyzed_by_day.keys + passed_by_day.keys).compact.uniq.sort
    days.map do |day|
      {
        date: day.to_s,
        total: total_by_day[day].to_i,
        analyzed: analyzed_by_day[day].to_i,
        passed: passed_by_day[day].to_i
      }
    end
  end

  # Conteo por estado SIN asumir el conjunto de valores: agrupa por la columna real
  # e incluye cualquier estado presente en los datos (pending, analyzed, error, etc.).
  def build_by_status
    analyses.group(:status).count.map do |status, count|
      { status: status, count: count }
    end.sort_by { |row| -row[:count] }
  end

  # Agregado por pipeline (pipeline_id es nullable: las filas sin pipeline van bajo nil).
  def build_by_pipeline
    counts = analyses.group(:pipeline_id).count
    analyzed = analyzed_scope.group(:pipeline_id).count
    passed = analyzed_scope.where(passed: true).group(:pipeline_id).count

    counts.map do |pipeline_id, total|
      ana = analyzed[pipeline_id].to_i
      pas = passed[pipeline_id].to_i
      {
        pipeline_id: pipeline_id,
        total: total,
        analyzed: ana,
        passed: pas,
        pass_rate: ana.zero? ? 0.0 : (pas.to_f / ana * 100).round(2)
      }
    end.sort_by { |row| -row[:total] }
  end

  # No-disponible: jabvox_cdr_call_analyses no tiene columna de agente/usuario ni
  # `extension`, por lo que no se puede cruzar con jabvox_cdr_extension_mappings.user_id.
  # TODO: si se agrega `extension` (o user_id) a jabvox_cdr_call_analyses, derivar el
  # agente uniendo por jabvox_cdr_extension_mappings (account_id + extension -> user_id).
  def build_by_agent
    {
      available: false,
      note: 'jabvox_cdr_call_analyses no tiene columna de agente/usuario ni `extension`; ' \
            'no es posible cruzar con jabvox_cdr_extension_mappings con el esquema actual.',
      rows: []
    }
  end
end
