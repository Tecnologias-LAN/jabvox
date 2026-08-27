# Runs a lead-source sync off the request cycle. Status/result land on the source
# row (last_sync_result_jabvox), which the UI polls.
#
# Robustez: un lock por source (Redis) impide que dos syncs del mismo source corran a la
# vez (evita duplicados que se pisan y disparan miles de export jobs). El estado nunca
# queda colgado: si el service falla, se marca 'error'; el lock expira solo.
class Jabvox::LeadImport::SyncJob < ApplicationJob
  queue_as :jabvox_lead_import

  # TTL base del lock; el heartbeat lo renueva mientras el sync corre, así una
  # cuenta con un import enorme nunca lo deja expirar a mitad (anti-duplicado).
  LOCK_TTL = 5.minutes.to_i

  def perform(lead_source_id)
    source = JabvoxLeadSource.find_by(id: lead_source_id)
    return unless source
    return unless source.account.feature_enabled?('jabvox_lead_import')

    result = Jabvox::RedisLock.with_lock("jabvox:lead_import:sync:#{lead_source_id}", ttl: LOCK_TTL) do |lock|
      run_sync(source, lead_source_id, lock)
    end
    Rails.logger.warn("[LeadImport::Sync] source=#{lead_source_id} ya en curso, omito") if result == Jabvox::RedisLock::NOT_ACQUIRED
  end

  private

  def run_sync(source, lead_source_id, lock)
    source.update!(status_jabvox: 'syncing')
    Jabvox::LeadImport::SyncService.new(source).call
    # Fencing: si perdimos el lock (proceso congelado > TTL y otro lo tomó), NO
    # marcamos 'ok' — el dueño actual del lock es el que manda.
    return unless lock.held?

    source.update!(status_jabvox: 'ok')
  rescue StandardError => e
    Rails.logger.error("[LeadImport::Sync] source=#{lead_source_id} error=#{e.message}")
    source&.update(status_jabvox: 'error',
                   last_sync_result_jabvox: { error: e.message, at: Time.current.iso8601 })
  end
end
