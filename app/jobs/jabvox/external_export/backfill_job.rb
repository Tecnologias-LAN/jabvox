# Runs a full backfill (since: nil) or an incremental reconcile (since: watermark)
# for one account's export target, off the request cycle and on a low-priority
# queue so it never competes with user-facing work.
#
# A short cache lock prevents two backfills for the same target from overlapping
# (the 5-minute scheduler could otherwise stack on top of a slow run). Progress
# and counters are stored on the target so the UI can show sync state.
class Jabvox::ExternalExport::BackfillJob < ApplicationJob
  queue_as :scheduled_jobs

  # Connection errors are transient; retry with backoff instead of hammering.
  retry_on Jabvox::ExternalExport::WriteAdapter::ConnectionError,
           wait: :polynomially_longer, attempts: 3

  LOCK_TTL = 30.minutes

  # incremental: when true, only export records updated since last_full_sync_at.
  def perform(account_id, incremental: false)
    account = Account.find_by(id: account_id)
    return unless account&.feature_enabled?('jabvox_data_export')

    target = account.jabvox_export_targets.active.first
    return unless target

    lock_key = "jabvox_export_backfill_lock/#{target.id}"
    return unless Rails.cache.write(lock_key, 1, unless_exist: true, expires_in: LOCK_TTL)

    begin
      since = incremental ? target.last_full_sync_at_jabvox : nil
      target.update_columns(sync_status_jabvox: 'syncing') # rubocop:disable Rails/SkipsModelValidations
      started = Time.current
      result = Jabvox::ExternalExport::BackfillService.new(target).call(since: since)
      # rubocop:disable Rails/SkipsModelValidations
      target.update_columns(
        sync_status_jabvox: 'ok',
        last_full_sync_at_jabvox: started,
        last_sync_result_jabvox: result,
        last_error_jabvox: nil
      )
      # rubocop:enable Rails/SkipsModelValidations
    ensure
      Rails.cache.delete(lock_key)
    end
  rescue Jabvox::ExternalExport::WriteAdapter::ConnectionError
    target&.update_columns(sync_status_jabvox: 'error') # rubocop:disable Rails/SkipsModelValidations
    raise # let retry_on handle it
  rescue StandardError => e
    Rails.logger.error("[ExternalExport::Backfill] account=#{account_id} #{e.class}: #{e.message}")
    target&.update_columns(sync_status_jabvox: 'error', last_error_jabvox: 'Error durante la sincronización') # rubocop:disable Rails/SkipsModelValidations
  end
end
