# frozen_string_literal: true

# Reporte "Llamadas" (key: calls).
#
# Combina dos fuentes de llamadas, ambas siempre acotadas a la cuenta vía la
# asociación de ActiveRecord (account.jabvox_call_logs / account.jabvox_dialer_call_logs):
#
#   1. jabvox_call_logs        -> llamadas individuales por agente (modelo "limpio").
#                                 Columnas: user_id, extension, status, uniqueid, called_at.
#   2. jabvox_dialer_call_logs -> llamadas del marcador predictivo/campañas.
#                                 Columnas equivalentes con sufijo _jabvox:
#                                 agent_id_jabvox, status_jabvox, uniqueid_jabvox, started_at_jabvox.
#                                 NO tiene columna `extension`.
#
# Agrega por extensión/agente y por día.
class Jabvox::Analytics::Reports::CallsReportService
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
      by_extension: build_by_extension,
      by_status: build_by_status
    }
  end

  private

  attr_reader :account, :date_from, :date_to, :filters

  # Id de agente solicitado (agent_id o user_id en @filters).
  def filter_agent_id
    @filter_agent_id ||= begin
      raw = filters['agent_id'].presence || filters['user_id'].presence
      raw && raw.to_i
    end
  end

  def filter_status
    filters['status'].presence
  end

  def filter_campaign_id
    @filter_campaign_id ||= filters['campaign_id'].presence&.to_i
  end

  # Fuente 1: llamadas individuales (tabla limpia). Acotada a la cuenta + fecha.
  # Filtros: user_id (agente) y status. No tiene campaña, por eso campaign_id no aplica.
  def call_logs
    scope = account.jabvox_call_logs
    scope = scope.where('jabvox_call_logs.called_at >= ?', date_from) if date_from.present?
    scope = scope.where('jabvox_call_logs.called_at <= ?', date_to) if date_to.present?
    scope = scope.where(user_id: filter_agent_id) if filter_agent_id
    scope = scope.where(status: filter_status) if filter_status
    scope
  end

  # Fuente 2: llamadas del marcador (columnas _jabvox). Acotada a la cuenta + fecha.
  # Filtros: agent_id_jabvox (agente), status_jabvox y jabvox_dialer_campaign_id (campaña).
  def dialer_call_logs
    scope = account.jabvox_dialer_call_logs
    scope = scope.where('jabvox_dialer_call_logs.started_at_jabvox >= ?', date_from) if date_from.present?
    scope = scope.where('jabvox_dialer_call_logs.started_at_jabvox <= ?', date_to) if date_to.present?
    scope = scope.where(agent_id_jabvox: filter_agent_id) if filter_agent_id
    scope = scope.where(status_jabvox: filter_status) if filter_status
    scope = scope.where(jabvox_dialer_campaign_id: filter_campaign_id) if filter_campaign_id
    scope
  end

  def build_summary
    individual = call_logs.count
    dialer = dialer_call_logs.count

    {
      total_calls: individual + dialer,
      individual_calls: individual,
      dialer_calls: dialer,
      dialer_answered: dialer_call_logs.where(lead_answered_jabvox: true).count,
      total_dialer_duration_seconds: dialer_call_logs.sum(:duration_jabvox).to_i,
      avg_dialer_duration_seconds: dialer_call_logs.average(:duration_jabvox).to_f.round(2)
    }
  end

  # Serie temporal por día, separando ambas fuentes y un total combinado.
  def build_series
    individual = call_logs.group('DATE(jabvox_call_logs.called_at)').count
    dialer = dialer_call_logs.group('DATE(jabvox_dialer_call_logs.started_at_jabvox)').count

    days = (individual.keys + dialer.keys).compact.uniq.sort
    days.map do |day|
      ind = individual[day].to_i
      dia = dialer[day].to_i
      {
        date: day.to_s,
        individual_calls: ind,
        dialer_calls: dia,
        total_calls: ind + dia
      }
    end
  end

  # Agregado por agente (user_id en una tabla, agent_id_jabvox en la otra).
  # agent_id_jabvox es nullable: las filas sin agente quedan bajo la clave nil.
  def build_by_agent
    individual = call_logs.group(:user_id).count
    dialer = dialer_call_logs.group(:agent_id_jabvox).count

    agent_ids = (individual.keys + dialer.keys).uniq
    agent_ids.map do |agent_id|
      ind = individual[agent_id].to_i
      dia = dialer[agent_id].to_i
      {
        agent_id: agent_id,
        individual_calls: ind,
        dialer_calls: dia,
        total_calls: ind + dia
      }
    end.sort_by { |row| -row[:total_calls] }
  end

  # Agregado por extensión. Solo jabvox_call_logs tiene la columna `extension`;
  # jabvox_dialer_call_logs NO la tiene, por eso esa fuente no aparece aquí.
  def build_by_extension
    rows = call_logs.group(:extension).count.map do |extension, count|
      { extension: extension, calls: count }
    end.sort_by { |row| -row[:calls] }

    {
      available: true,
      source: 'jabvox_call_logs',
      note: 'jabvox_dialer_call_logs no tiene columna `extension`; solo se cuentan las llamadas individuales.',
      rows: rows
    }
  end

  # Agregado por estado (status vs status_jabvox).
  def build_by_status
    individual = call_logs.group(:status).count.map do |status, count|
      { status: status, calls: count }
    end.sort_by { |row| -row[:calls] }

    dialer = dialer_call_logs.group(:status_jabvox).count.map do |status, count|
      { status: status, calls: count }
    end.sort_by { |row| -row[:calls] }

    {
      individual: individual,
      dialer: dialer
    }
  end
end
