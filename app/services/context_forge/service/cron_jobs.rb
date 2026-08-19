# frozen_string_literal: true

# Operaciones de cron jobs de Hermes para ContextForge::Service. Todas usan el SCOPED
# TOKEN de la cuenta: el scoped token acota el profile, así que con el token de la cuenta N
# solo se ven/gestionan SUS cron jobs (Hermes responde 403 al token de otra cuenta). El
# cliente HTTP apunta al gateway de Hermes (hermes_url), que es quien tiene el scheduler.
module ContextForge::Service::CronJobs
  # Lista los cron jobs de la cuenta (scoped por token).
  def list_cron_jobs(scoped_token)
    resp = hermes_scoped_client(scoped_token).get(ContextForge::Service::PATHS[:cron])
    build_result(resp)
  rescue Faraday::Error, ContextForge::Service::ConfigurationError, URI::Error => e
    failure(call_error_message(e))
  end

  # Crea un cron job. attrs: { name:, schedule: (cron expr), prompt:/blueprint:, enabled: }
  def create_cron_job(scoped_token, attrs)
    resp = hermes_scoped_client(scoped_token).post(ContextForge::Service::PATHS[:cron]) { |r| r.body = attrs }
    build_result(resp)
  rescue Faraday::Error, ContextForge::Service::ConfigurationError, URI::Error => e
    failure(call_error_message(e))
  end

  # Pausa/reanuda un cron job (enabled: true/false).
  def set_cron_job_enabled(scoped_token, job_id, enabled)
    resp = hermes_scoped_client(scoped_token).patch("#{ContextForge::Service::PATHS[:cron]}/#{job_id}") do |r|
      r.body = { enabled: enabled }
    end
    build_result(resp)
  rescue Faraday::Error, ContextForge::Service::ConfigurationError, URI::Error => e
    failure(call_error_message(e))
  end

  # Elimina un cron job.
  def delete_cron_job(scoped_token, job_id)
    resp = hermes_scoped_client(scoped_token).delete("#{ContextForge::Service::PATHS[:cron]}/#{job_id}")
    build_result(resp)
  rescue Faraday::Error, ContextForge::Service::ConfigurationError, URI::Error => e
    failure(call_error_message(e))
  end

  private

  # Cliente hacia el gateway de Hermes con el scoped token de la cuenta (para cron).
  def hermes_scoped_client(token)
    url = ContextForge::Service.hermes_url
    raise ContextForge::Service::ConfigurationError, 'Hermes URL ausente' if url.blank?

    build_connection(url) { |f| f.headers['Authorization'] = "Bearer #{token}" }
  end
end
