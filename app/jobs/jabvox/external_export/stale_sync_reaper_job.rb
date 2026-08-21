# frozen_string_literal: true

# Red de seguridad para data-export: si un BackfillJob muere antes de su rescue
# (OOM, reinicio, worker caído), el target queda en sync_status 'syncing' para
# siempre. Este cron marca 'error' todo target cuyo 'syncing' lleve demasiado
# tiempo; el reconcile scheduler lo re-intentará en la siguiente pasada.
class Jabvox::ExternalExport::StaleSyncReaperJob < ApplicationJob
  queue_as :jabvox_export

  STALE_AFTER = 1.hour

  def perform
    count = JabvoxExportTarget.where(sync_status_jabvox: 'syncing')
                              .where(updated_at: ..STALE_AFTER.ago)
                              .update_all( # rubocop:disable Rails/SkipsModelValidations
                                sync_status_jabvox: 'error',
                                updated_at: Time.current
                              )
    Rails.logger.info("[ExternalExport::StaleSyncReaper] targets liberados: #{count}") if count.positive?
  end
end
