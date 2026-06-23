# frozen_string_literal: true

# Reporte interno de Análisis de Audio para el módulo Analytics de Jabvox.
#
# Fuente principal: jabvox_audio_results (siempre acotado por la cuenta vía la
# asociación account.jabvox_audio_results, nunca un scope global).
#
# Métricas: total de análisis, aprobados/rechazados (passed), pendientes
# (status pending + processing), score promedio (final_score), tiempo de
# procesamiento promedio (processing_time_ms) y distribución de sentimiento.
# Agrupa por estado (status), por sentimiento (sentiment), por agente asignado
# (assigned_agent_id) y por día sobre created_at.
#
# NOTA de esquema: en jabvox_audio_results el FK de agente es assigned_agent_id
# (NO agent_id ni user_id). El estado vive en la columna string status, sin enum
# en BD; "Pendiente" = status IN ('pending', 'processing').
class Jabvox::Analytics::Reports::AudioAnalysisReportService
  PENDING_STATUSES = %w[pending processing].freeze

  def initialize(account:, date_from: nil, date_to: nil, filters: {})
    raise ArgumentError, 'account is required' if account.nil?

    @account = account
    @date_from = date_from
    @date_to = date_to
    @filters = filters || {}
  end

  def call
    {
      summary: summary,
      series: series,
      by_status: by_status,
      by_sentiment: by_sentiment,
      by_agent: by_agent
    }
  end

  private

  attr_reader :account, :date_from, :date_to, :filters

  # Scope base: SIEMPRE arranca de la asociación de la cuenta. Los filtros
  # adicionales (agente asignado, status, sentimiento) solo se aplican si vienen.
  def scope
    relation = account.jabvox_audio_results
    relation = relation.where('jabvox_audio_results.created_at >= ?', date_from) if date_from.present?
    relation = relation.where('jabvox_audio_results.created_at <= ?', date_to) if date_to.present?
    relation = relation.where(assigned_agent_id: filter_agent_id) if filter_agent_id
    relation = relation.where(status: filters['status']) if filters['status'].present?
    relation = relation.where(sentiment: filters['sentiment']) if filters['sentiment'].present?
    relation
  end

  # Id de agente solicitado (agent_id o user_id en @filters). FK real: assigned_agent_id.
  def filter_agent_id
    @filter_agent_id ||= begin
      raw = filters['agent_id'].presence || filters['user_id'].presence
      raw && raw.to_i
    end
  end

  def summary
    total = scope.count
    passed = scope.where(passed: true).count
    pending = scope.where(status: PENDING_STATUSES).count
    avg_score = scope.where.not(final_score: nil).average(:final_score)
    avg_time = scope.where.not(processing_time_ms: nil).average(:processing_time_ms)
    {
      total_analyses: total,
      passed: passed,
      failed: total - passed,
      pending: pending,
      pass_rate: total.positive? ? (passed.to_f / total * 100).round(2) : 0.0,
      average_score: avg_score ? avg_score.to_f.round(2) : nil,
      average_processing_time_ms: avg_time ? avg_time.to_f.round(2) : nil
    }
  end

  # Serie temporal por día sobre created_at: total de análisis y aprobados.
  def series
    created = scope.group('DATE(jabvox_audio_results.created_at)').count
    passed = scope.where(passed: true).group('DATE(jabvox_audio_results.created_at)').count
    days = (created.keys + passed.keys).uniq.sort
    days.map do |day|
      {
        date: day.to_s,
        total: created[day] || 0,
        passed: passed[day] || 0
      }
    end
  end

  def by_status
    scope.group(:status).count.map do |status, count|
      { status: status, count: count }
    end
  end

  def by_sentiment
    scope.group(:sentiment).count.map do |sentiment, count|
      { sentiment: sentiment, count: count }
    end
  end

  # Atribución por agente asignado. FK real: assigned_agent_id (→ users).
  # Promedio de score por agente además del conteo de análisis.
  def by_agent
    counts = scope.group(:assigned_agent_id).count
    avg_scores = scope.where.not(final_score: nil).group(:assigned_agent_id).average(:final_score)
    counts.map do |agent_id, count|
      avg = avg_scores[agent_id]
      {
        agent_id: agent_id,
        name: agent_name(agent_id),
        count: count,
        average_score: avg ? avg.to_f.round(2) : nil
      }
    end
  end

  def agent_name(agent_id)
    return nil if agent_id.nil?

    agent_names[agent_id]
  end

  # Nombres de agentes acotados a los usuarios de la cuenta (asociación), en una
  # sola query. Cualquier assigned_agent_id ajeno a la cuenta quedará sin nombre.
  def agent_names
    @agent_names ||= account.users.pluck(:id, :name).to_h
  end
end
