# frozen_string_literal: true

# Reconciliación del Drive para UNA cuenta. Lo encola el cron
# (ReconcileSchedulerJob). Delega en ReconciliationService#reconcile!, que es
# idempotente: marcar objetos faltantes, registrar huérfanos y, sobre todo,
# REINDEXAR los adjuntos que están en MinIO pero sin fila en el Drive (red de
# seguridad del sync).
#
# Un lock por cuenta evita que dos pases se solapen (el barrido es barato pero no
# queremos reencolar la misma ingesta dos veces en paralelo).
class Jabvox::Drive::ReconcileAccountJob < MutexApplicationJob
  queue_as :jabvox_drive

  retry_on LockAcquisitionError, wait: 10.seconds, attempts: 3

  def perform(account_id)
    account = Account.find_by(id: account_id)
    return if account.nil?
    return unless account.feature_enabled?('jabvox_drive')

    key = "jabvox_drive_reconcile_account_#{account_id}"
    with_lock(key, 5.minutes) do
      Jabvox::Drive::ReconciliationService.new(account).reconcile!
    end
  end
end
