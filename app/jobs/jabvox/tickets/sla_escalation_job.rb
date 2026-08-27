# Job recurrente (cada 15 min vía sidekiq-cron): detecta tickets abiertos vencidos
# que aún no fueron escalados, les sube la prioridad, lo registra en la bitácora y
# notifica a los resolvers. Usa columnas reales (sla_escalated_at_jabvox) e índices
# parciales, no scan de jsonb. Instrumenta la corrida para observabilidad.
class Jabvox::Tickets::SlaEscalationJob < ApplicationJob
  queue_as :scheduled_jobs

  # Clave Redis del último latido exitoso (para vigilar que el cron sigue vivo).
  HEARTBEAT_KEY = 'jabvox_tickets:sla_job:last_run_at'.freeze

  def perform
    started = current_time
    escalated = run_escalations

    record_heartbeat
    log_run(escalated, started)
  rescue StandardError => e
    # Reporta al tracker (no muere en silencio): un job de vencimientos que falla
    # calladamente es peor que no tenerlo.
    JabvoxExceptionTracker.new(e).capture_exception
    raise
  end

  # Último instante en que el job corrió con éxito (nil si nunca o si Redis falla).
  def self.last_run_at
    raw = Redis::Alfred.get(HEARTBEAT_KEY)
    raw && Time.zone.parse(raw)
  rescue StandardError
    nil
  end

  private

  def record_heartbeat
    Redis::Alfred.set(HEARTBEAT_KEY, current_time.iso8601)
  rescue StandardError => e
    JabvoxExceptionTracker.new(e).capture_exception
  end

  def run_escalations
    count = 0
    JabvoxTicket.sla_pending_escalation.find_each do |ticket|
      escalate(ticket)
      count += 1
    rescue StandardError => e
      JabvoxExceptionTracker.new(e, account: ticket.account).capture_exception
    end
    count
  end

  def escalate(ticket)
    previous = ticket.priority_jabvox
    ticket.update!(priority_jabvox: bump_priority(previous), sla_escalated_at_jabvox: current_time)
    ticket.log_activity!('sla_escalated', from: previous, to: ticket.priority_jabvox)
    Jabvox::Tickets::NotificationService.new(ticket).sla_escalated
  end

  # Sube un nivel de prioridad (tope en urgent).
  def bump_priority(current)
    order = JabvoxTicket.priority_jabvoxes.keys
    idx = order.index(current.to_s)
    order[[idx + 1, order.length - 1].min]
  end

  def log_run(escalated, started)
    Rails.logger.info(
      { event: 'jabvox_tickets.sla_escalation', escalated: escalated,
        duration_ms: ((current_time - started) * 1000).round }.to_json
    )
  end

  def current_time
    Time.current
  end
end
