# frozen_string_literal: true

# Reporte "CSAT" (key: csat).
#
# Mide la satisfacción del cliente a partir de las respuestas de encuesta CSAT,
# SIEMPRE acotadas a la cuenta vía la asociación account.csat_survey_responses
# (sin SQL crudo con account_id interpolado, sin `.all` global):
#
#   csat_survey_responses -> una fila por respuesta. Campos relevantes:
#     rating (1..5), assigned_agent_id (agente resuelto vía users.name),
#     conversation_id, contact_id, created_at.
#
# Definiciones:
#   - "satisfecho" = rating >= 4.
#   - distribución = conteo por cada valor de rating 1..5 (incluye los ceros).
#
# Salida: summary con totales/promedio/%satisfechos, series temporal por día,
# by_agent (merge/resolución de nombre en Ruby) y by_rating (distribución).
class Jabvox::Analytics::Reports::CsatReportService
  SATISFIED_THRESHOLD = 4
  RATINGS = (1..5)

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
      by_agent: build_by_agent,
      by_rating: build_by_rating
    }
  end

  private

  attr_reader :account, :date_from, :date_to, :filters

  # Id de agente solicitado (agent_id o user_id en @filters). FK real: assigned_agent_id.
  def filter_agent_id
    @filter_agent_id ||= begin
      raw = filters['agent_id'].presence || filters['user_id'].presence
      raw && raw.to_i
    end
  end

  # ---- Scope (siempre acotado a la cuenta) -------------------------------

  # Respuestas CSAT de la cuenta + ventana por created_at. Filtro: assigned_agent_id.
  def responses
    scope = account.csat_survey_responses
    scope = scope.where('csat_survey_responses.created_at >= ?', date_from) if date_from.present?
    scope = scope.where('csat_survey_responses.created_at <= ?', date_to) if date_to.present?
    scope = scope.where(assigned_agent_id: filter_agent_id) if filter_agent_id
    scope
  end

  # ---- Métricas agregadas ------------------------------------------------

  def build_summary
    total = responses.count
    satisfied = responses.where('csat_survey_responses.rating >= ?', SATISFIED_THRESHOLD).count

    {
      total_responses: total,
      average_rating: responses.average(:rating).to_f.round(2),
      satisfied_responses: satisfied,
      satisfaction_rate: percentage(satisfied, total)
    }
  end

  # Serie temporal por día: número de respuestas y promedio de rating.
  def build_series
    counts = responses.group('DATE(csat_survey_responses.created_at)').count
    averages = responses.group('DATE(csat_survey_responses.created_at)').average(:rating)

    counts.keys.compact.sort.map do |day|
      {
        date: day.to_s,
        responses: counts[day].to_i,
        average_rating: averages[day].to_f.round(2)
      }
    end
  end

  # Una fila por agente (assigned_agent_id). El nombre se resuelve con un único
  # query acotado a la cuenta (account.users). Las respuestas sin agente quedan
  # agrupadas bajo "Sin asignar".
  def build_by_agent
    counts = responses.group(:assigned_agent_id).count
    averages = responses.group(:assigned_agent_id).average(:rating)
    satisfied = responses.where('csat_survey_responses.rating >= ?', SATISFIED_THRESHOLD)
                         .group(:assigned_agent_id).count
    names = account.users.where(id: counts.keys.compact).pluck(:id, :name).to_h

    rows = counts.map { |agent_id, total| agent_row(agent_id, total, names, averages, satisfied) }
    rows.sort_by { |row| -row[:total_responses] }
  end

  def agent_row(agent_id, total, names, averages, satisfied)
    {
      agent_id: agent_id,
      agent_name: agent_name(agent_id, names),
      total_responses: total,
      average_rating: averages[agent_id].to_f.round(2),
      satisfied_responses: satisfied[agent_id].to_i,
      satisfaction_rate: percentage(satisfied[agent_id].to_i, total)
    }
  end

  # Distribución por valor de rating (1..5), incluyendo los que no aparecen (0).
  def build_by_rating
    counts = responses.group(:rating).count
    total = counts.values.sum

    RATINGS.map do |rating|
      count = counts[rating].to_i
      {
        rating: rating,
        count: count,
        percentage: percentage(count, total)
      }
    end
  end

  # ---- Helpers -----------------------------------------------------------

  def agent_name(agent_id, names)
    return 'Sin asignar' if agent_id.nil?

    names[agent_id] || "Agente ##{agent_id}"
  end

  def percentage(part, total)
    return 0.0 if total.to_i.zero?

    ((part.to_f / total) * 100).round(2)
  end
end
