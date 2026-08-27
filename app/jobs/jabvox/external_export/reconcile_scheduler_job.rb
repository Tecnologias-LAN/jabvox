# Cron entrypoint (every 5 minutes). For each account with the data-export
# feature and an active target, enqueues an INCREMENTAL backfill so anything the
# real-time after_commit mirror missed is reconciled. The per-target cache lock
# in BackfillJob keeps a slow run from stacking; nothing runs inline here, so the
# scheduler stays cheap regardless of how many accounts export.
class Jabvox::ExternalExport::ReconcileSchedulerJob < ApplicationJob
  queue_as :jabvox_export

  # Si la cola aún arrastra backlog de la corrida anterior (export lento a escala),
  # saltamos esta pasada para no encolar más rápido de lo que se drena.
  BACKLOG_CEILING = 2000

  def perform
    if queue_backlogged?
      Rails.logger.warn('[ExternalExport::Reconcile] backlog alto en jabvox_export; salto esta corrida')
      return
    end

    # No hay outbox: no se puede saber en O(log n) qué cuenta tiene filas
    # pendientes sin escanear (eso lo hace el BackfillService). Lo que sí evitamos
    # es re-encolar un target que YA está sincronizando (un backfill en curso);
    # el lock por target del BackfillJob también lo cubre, pero filtrar aquí ahorra
    # el encolado y el arranque en vano.
    JabvoxExportTarget.active
                      .where.not(sync_status_jabvox: 'syncing')
                      .distinct
                      .pluck(:account_id)
                      .each do |account_id|
      next unless Jabvox::ExternalExport.export_enabled?(account_id)

      Jabvox::ExternalExport::BackfillJob.perform_later(account_id, incremental: true)
    rescue StandardError => e
      Rails.logger.error("[ExternalExport::Reconcile] account=#{account_id} #{e.class}: #{e.message}")
    end
  end

  private

  def queue_backlogged?
    Sidekiq::Queue.new('jabvox_export').size > BACKLOG_CEILING
  rescue StandardError
    false
  end
end
