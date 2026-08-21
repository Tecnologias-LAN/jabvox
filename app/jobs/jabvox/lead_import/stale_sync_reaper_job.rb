# frozen_string_literal: true

# Red de seguridad para lead-import: si un SyncJob muere antes de su rescue
# (OOM, reinicio del servidor, worker caído), la fuente queda en 'syncing' para
# siempre y la UI la muestra colgada. Este cron marca 'error' toda fuente cuyo
# 'syncing' lleve demasiado tiempo, para que el usuario pueda relanzar.
class Jabvox::LeadImport::StaleSyncReaperJob < ApplicationJob
  queue_as :jabvox_lead_import

  STALE_AFTER = 2.hours

  def perform
    stale = JabvoxLeadSource.where(status_jabvox: 'syncing')
                            .where(updated_at: ..STALE_AFTER.ago)
    # find_each + update (no update_all) para que el casteo de la columna jsonb
    # lo haga ActiveRecord; el volumen de fuentes colgadas es pequeño.
    count = 0
    stale.find_each do |source|
      source.update_columns( # rubocop:disable Rails/SkipsModelValidations
        status_jabvox: 'error',
        last_sync_result_jabvox: { error: 'Sincronización interrumpida (worker o servidor reiniciado)', at: Time.current.iso8601 },
        updated_at: Time.current
      )
      count += 1
    end
    Rails.logger.info("[LeadImport::StaleSyncReaper] fuentes liberadas: #{count}") if count.positive?
  end
end
