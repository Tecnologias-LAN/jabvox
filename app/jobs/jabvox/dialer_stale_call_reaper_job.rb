# Reaper de llamadas huérfanas del dialer (cron cada 1 min).
#
# El ciclo del dialer cierra cada llamada cuando el AMI listener procesa el
# Hangup en vivo. Pero si el listener pierde ese evento — reconexión del socket,
# reinicio del servicio en un deploy, un Getvar desincronizado, o un dialplan que
# no propaga JABVOX_DIALER_LOG_ID — el call log queda 'initiated'/'calling' y el
# campaign_contact queda 'calling' PARA SIEMPRE: el lead nunca se vuelve a marcar
# y el monitor lo muestra como llamada en curso eterna.
#
# Este reaper es la red de seguridad definitiva: cierra por tiempo todo lo que
# lleve demasiado abierto (ninguna llamada real dura tanto), para que el marcador
# nunca se quede pegado pase lo que pase con la telefonía.
class Jabvox::DialerStaleCallReaperJob < ApplicationJob
  queue_as :jabvox_ami

  # Ventana de gracia. Una llamada real (timbrado + conversación) no supera unos
  # minutos; 15 min es holgado y jamás toca una llamada viva.
  STALE_AFTER = 15.minutes

  def perform
    cutoff = STALE_AFTER.ago

    # 1) Call logs abiertos demasiado viejos → no_answer + cerrados.
    stale_logs = JabvoxDialerCallLog
                 .where(status_jabvox: %w[initiated calling])
                 .where('COALESCE(started_at_jabvox, created_at) < ?', cutoff)
    stale_logs.find_each do |log|
      finalize_stale_log(log)
    rescue StandardError => e
      Rails.logger.error("[DialerReaper] log=#{log.id} #{e.class}: #{e.message}")
    end

    # 2) Campaign contacts pegados en 'calling' → no_answer, para que el picker
    #    los libere (el retry, si aplica, decide si se re-marcan).
    stale_contacts = JabvoxDialerCampaignContact
                     .where(status_jabvox: 'calling')
                     .where('COALESCE(last_attempt_at_jabvox, updated_at) < ?', cutoff)
    count = stale_contacts.update_all(status_jabvox: 'no_answer', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

    reaped_logs = stale_logs.size
    return if reaped_logs.zero? && count.zero?

    Rails.logger.info("[DialerReaper] cerrados #{reaped_logs} call logs y #{count} contactos huérfanos")
  end

  private

  # rubocop:disable Rails/SkipsModelValidations
  def finalize_stale_log(log)
    started = log.started_at_jabvox || log.created_at
    log.update_columns(
      status_jabvox: 'no_answer',
      lead_answered_jabvox: false,
      ended_at_jabvox: log.ended_at_jabvox || Time.current,
      duration_jabvox: log.duration_jabvox.to_i.positive? ? log.duration_jabvox : 0,
      updated_at: Time.current
    )
    cc = JabvoxDialerCampaignContact.find_by(id: log.jabvox_dialer_campaign_contact_id)
    cc&.update_columns(status_jabvox: 'no_answer', updated_at: Time.current) if cc&.status_jabvox == 'calling'
    started
  end
  # rubocop:enable Rails/SkipsModelValidations
end
