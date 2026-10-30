# frozen_string_literal: true

# Entrada del cron de reconciliación del Drive (cada 15 min).
#
# Hace fan-out a un ReconcileAccountJob por cada cuenta con actividad de Drive. La
# reconciliación por cuenta (ReconciliationService#reconcile!) hace tres cosas
# idempotentes y baratas:
#   - marca quarantined las filas cuyo objeto ya no existe en MinIO,
#   - registra objetos en MinIO sin fila (log),
#   - REINDEXA los adjuntos de mensajes recientes que están en MinIO pero sin fila
#     en el Drive (red de seguridad del sync: si el enganche after_create_commit no
#     corrió, aquí se recupera el adjunto sin intervención manual).
#
# Barato a escala: solo toca cuentas que YA tienen storage_account (es decir, que han
# usado el Drive), y cada ReconcileAccountJob solo revisa la ventana reciente.
class Jabvox::Drive::ReconcileSchedulerJob < ApplicationJob
  queue_as :jabvox_drive

  # Despachado por sidekiq-cron (el siguiente ciclo recupera lo que falte).
  # NO usar `sidekiq_options`: no existe en ApplicationJob (ActiveJob) y era lo que
  # hacía fallar el job con `undefined method 'jid='` al invocarlo desde sidekiq-cron.

  BATCH_SIZE = 500

  def perform
    JabvoxDriveStorageAccount.select(:account_id).find_each(batch_size: BATCH_SIZE) do |row|
      Jabvox::Drive::ReconcileAccountJob.perform_later(row.account_id)
    rescue StandardError => e
      Rails.logger.error("[Jabvox::Drive::ReconcileSchedulerJob] account=#{row.account_id} #{e.class}: #{e.message}")
    end
  end
end
