# Reporte interno "Email" del modulo Analytics de Jabvox.
#
# Cuenta los envios reales registrados en jabvox_email_send_logs (poblados por
# Jabvox::EmailSenderService en cada punto de envio) + la cifra de plantillas.
#
# Seguridad: toda consulta arranca de account.jabvox_email_send_logs /
# account.jabvox_email_templates, nunca de un .all global ni SQL crudo. El
# account_id viaja siempre por ActiveRecord.
class Jabvox::Analytics::Reports::EmailReportService
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
      by_source: by_source,
      templates: templates_summary
    }
  end

  private

  attr_reader :account, :date_from, :date_to, :filters

  # Id de agente solicitado (agent_id o user_id en @filters). FK real: user_id.
  def filter_agent_id
    @filter_agent_id ||= begin
      raw = filters['agent_id'].presence || filters['user_id'].presence
      raw && raw.to_i
    end
  end

  # Envios de email de esta cuenta, acotados por created_at si hay rango.
  # Filtros: user_id (agente), status (sent/failed) y source (manual/kanban/...).
  def sends_scope
    rel = account.jabvox_email_send_logs
    rel = rel.where('jabvox_email_send_logs.created_at >= ?', date_from) if date_from.present?
    rel = rel.where('jabvox_email_send_logs.created_at <= ?', date_to) if date_to.present?
    rel = rel.where(user_id: filter_agent_id) if filter_agent_id
    rel = rel.where(status: filters['status']) if filters['status'].present?
    rel = rel.where(source: filters['source']) if filters['source'].present?
    rel
  end

  def summary
    counts = sends_scope.group(:status).count
    sent = counts['sent'].to_i
    failed = counts['failed'].to_i
    total = sent + failed

    {
      total_sent: total,
      delivered: sent,
      failed: failed,
      delivery_rate: total.positive? ? (sent.to_f / total * 100).round(2) : 0.0
    }
  end

  # Envios por dia dentro del rango.
  def series
    sends_scope
      .group('DATE(jabvox_email_send_logs.created_at)')
      .order('DATE(jabvox_email_send_logs.created_at)')
      .count
      .map { |date, count| { date: date.to_s, sent: count } }
  end

  # Distribucion enviados vs fallidos.
  def by_status
    counts = sends_scope.group(:status).count
    [
      { status: 'sent', label: 'Enviados', count: counts['sent'].to_i },
      { status: 'failed', label: 'Fallidos', count: counts['failed'].to_i }
    ]
  end

  # Envios por origen (manual / kanban / task / calendar / form / system).
  def by_source
    sends_scope.group(:source).count.map do |source, count|
      { source: source, count: count }
    end
  end

  # Cifra de plantillas configuradas (no acotada por fecha de envio).
  def templates_summary
    counts = account.jabvox_email_templates.group(:active).count
    {
      total: counts.values.sum,
      active: counts[true].to_i,
      inactive: counts[false].to_i
    }
  end
end
