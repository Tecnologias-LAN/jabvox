# Cron entrypoint (every 5 minutes). For each account with the data-export
# feature and an active target, enqueues an INCREMENTAL backfill so anything the
# real-time after_commit mirror missed is reconciled. The per-target cache lock
# in BackfillJob keeps a slow run from stacking; nothing runs inline here, so the
# scheduler stays cheap regardless of how many accounts export.
class Jabvox::ExternalExport::ReconcileSchedulerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    JabvoxExportTarget.active
                      .distinct
                      .pluck(:account_id)
                      .each do |account_id|
      next unless Jabvox::ExternalExport.export_enabled?(account_id)

      Jabvox::ExternalExport::BackfillJob.perform_later(account_id, incremental: true)
    rescue StandardError => e
      Rails.logger.error("[ExternalExport::Reconcile] account=#{account_id} #{e.class}: #{e.message}")
    end
  end
end
