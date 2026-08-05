# Tareas de mantenimiento/observabilidad del módulo de tickets.
namespace :jabvox_tickets do
  # Vigila el job de SLA: si no ha corrido con éxito en más de STALE_AFTER, reporta
  # al tracker de errores para que alguien se entere (el job de vencimientos no debe
  # morir en silencio). Pensado para correr desde un cron externo o un check de salud.
  #
  #   bundle exec rake jabvox_tickets:check_sla_job_health
  desc 'Alerta si el job de escalamiento SLA dejó de correr'
  task check_sla_job_health: :environment do
    stale_after_minutes = 45 # tres ciclos de 15 min
    # Sin cuenta gestora configurada, el job no tiene nada que hacer: no alertar.
    next if JabvoxTicketHelpdeskConfig.manager_account.nil?

    last_run = Jabvox::Tickets::SlaEscalationJob.last_run_at
    threshold = stale_after_minutes.minutes.ago

    if last_run.nil? || last_run < threshold
      message = "SLA escalation job stale. last_run=#{last_run || 'never'} threshold=#{threshold}"
      Rails.logger.error({ event: 'jabvox_tickets.sla_job_stale', last_run: last_run&.iso8601 }.to_json)
      JabvoxExceptionTracker.new(StandardError.new(message)).capture_exception
      puts "ALERT: #{message}"
    else
      puts "OK: SLA job last ran at #{last_run.iso8601}"
    end
  end
end
