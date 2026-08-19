# Runs a lead-source sync off the request cycle. Status/result land on the source
# row (last_sync_result_jabvox), which the UI polls.
#
# Robustez: un lock por source (Redis) impide que dos syncs del mismo source corran a la
# vez (evita duplicados que se pisan y disparan miles de export jobs). El estado nunca
# queda colgado: si el service falla, se marca 'error'; el lock expira solo.
class Jabvox::LeadImport::SyncJob < ApplicationJob
  queue_as :default

  LOCK_TTL = 2.hours # tope de duración de un sync; el lock se libera solo pasado esto

  def perform(lead_source_id)
    source = JabvoxLeadSource.find_by(id: lead_source_id)
    return unless source
    return unless source.account.feature_enabled?('jabvox_lead_import')

    lock_key = "jabvox:lead_import:sync:#{lead_source_id}"
    got_lock = acquire_lock(lock_key)
    # Si ya hay un sync corriendo para este source, no arrancamos otro (anti-duplicado).
    return Rails.logger.warn("[LeadImport::Sync] source=#{lead_source_id} ya en curso, omito") unless got_lock

    run_sync(source, lead_source_id)
  ensure
    release_lock(lock_key) if got_lock
  end

  private

  def run_sync(source, lead_source_id)
    source.update!(status_jabvox: 'syncing')
    Jabvox::LeadImport::SyncService.new(source).call
    source.update!(status_jabvox: 'ok')
  rescue StandardError => e
    Rails.logger.error("[LeadImport::Sync] source=#{lead_source_id} error=#{e.message}")
    source&.update(status_jabvox: 'error',
                   last_sync_result_jabvox: { error: e.message, at: Time.current.iso8601 })
  end

  # Lock atómico en Redis (SET NX EX). Devuelve true si lo obtuvo.
  def acquire_lock(key)
    Sidekiq.redis { |r| r.set(key, Time.now.to_i, nx: true, ex: LOCK_TTL.to_i) }
  rescue StandardError
    true # si Redis falla, no bloqueamos el sync (mejor correr que no correr)
  end

  def release_lock(key)
    Sidekiq.redis { |r| r.del(key) }
  rescue StandardError
    nil
  end
end
