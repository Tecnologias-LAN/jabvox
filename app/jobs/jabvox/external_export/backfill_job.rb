# Runs a full backfill (since: nil) or an incremental reconcile (since: watermark)
# for one account's export target, off the request cycle and on a low-priority
# queue so it never competes with user-facing work.
#
# A short cache lock prevents two backfills for the same target from overlapping
# (the 5-minute scheduler could otherwise stack on top of a slow run). Progress
# and counters are stored on the target so the UI can show sync state.
class Jabvox::ExternalExport::BackfillJob < ApplicationJob
  queue_as :jabvox_export

  # Connection errors are transient; retry with backoff instead of hammering.
  retry_on Jabvox::ExternalExport::WriteAdapter::ConnectionError,
           wait: :polynomially_longer, attempts: 3

  # TTL base del lock; el heartbeat lo renueva mientras el backfill corre, así una
  # cuenta grande (backfill largo por lotes) nunca lo deja expirar a mitad.
  LOCK_TTL = 60

  # incremental: when true, only export records updated since last_full_sync_at.
  def perform(account_id, incremental: false)
    account = Account.find_by(id: account_id)
    return unless account&.feature_enabled?('jabvox_data_export')

    target = account.jabvox_export_targets.active.first
    return unless target

    Jabvox::RedisLock.with_lock("jabvox_export_backfill_lock/#{target.id}", ttl: LOCK_TTL) do |lock|
      run_sync(target, incremental, lock)
    end
  rescue Jabvox::ExternalExport::WriteAdapter::ConnectionError
    target&.update_columns(sync_status_jabvox: 'error') # rubocop:disable Rails/SkipsModelValidations
    raise # let retry_on handle it
  rescue StandardError => e
    Rails.logger.error("[ExternalExport::Backfill] account=#{account_id} #{e.class}: #{e.message}")
    target&.update_columns(sync_status_jabvox: 'error', last_error_jabvox: 'Error durante la sincronización') # rubocop:disable Rails/SkipsModelValidations
  end

  private

  # rubocop:disable Rails/SkipsModelValidations
  def run_sync(target, incremental, lock)
    since = incremental ? target.last_full_sync_at_jabvox : nil
    target.update_columns(sync_status_jabvox: 'syncing')
    started = Time.current
    # On a FULL sync ("Sincronizar ahora" / enabling), (re)build the schema first
    # so every table and column exists (incl. newly added ones like created_by_id,
    # question_key). Self-healing: it deploys EVERYTHING for the account from
    # scratch and never fails with "relation/column does not exist".
    Jabvox::ExternalExport::SchemaBuilderService.new(target).call unless incremental
    result = Jabvox::ExternalExport::BackfillService.new(target).call(since: since)
    # Fencing: si perdimos el lock (proceso congelado > TTL, otro backfill lo tomó),
    # no pisamos el estado con nuestro 'ok'; el dueño actual escribirá el suyo.
    return unless lock.held?

    target.update_columns(
      sync_status_jabvox: 'ok',
      last_full_sync_at_jabvox: started,
      last_sync_result_jabvox: result,
      last_error_jabvox: nil
    )
  end
  # rubocop:enable Rails/SkipsModelValidations
end
