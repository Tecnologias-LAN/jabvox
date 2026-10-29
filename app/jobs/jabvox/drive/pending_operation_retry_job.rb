# frozen_string_literal: true

# Scheduler de la cola DURABLE del Drive. Corre cada 1-2 min (sidekiq-cron) y
# reencola el job adecuado para cada operación `due` (pending y con el instante
# de reintento ya cumplido). Es la red de seguridad que garantiza que, aunque un
# worker muriera a mitad de un trabajo o MinIO estuviera caído, ninguna operación
# se quede atascada: aquí se vuelve a despachar.
#
# No procesa nada en línea (salvo el borrado de objetos, que es barato): solo
# despacha. El job concreto (p. ej. MediaIngestJob) es idempotente y vuelve a
# dejar la operación pending/failed según corresponda.
class Jabvox::Drive::PendingOperationRetryJob < ApplicationJob
  queue_as :jabvox_drive

  # Despachado por sidekiq-cron: sin reintentos (corre cada 2 min, el siguiente ciclo
  # recupera lo que falte). `sidekiq_options` además alinea el job con sidekiq-cron para
  # que lo encole como ActiveJob y no falle con `undefined method 'jid='`.
  sidekiq_options retry: 0

  BATCH_SIZE = 500

  def perform
    # Recuperación tras caída/reinicio del worker: las operaciones que quedaron
    # `processing` (worker murió a mitad) se devuelven a `pending` para reprocesarlas.
    # El procesamiento es idempotente, así que no se duplica nada.
    JabvoxDrivePendingOperation.recover_stale_processing!

    JabvoxDrivePendingOperation.due.find_each(batch_size: BATCH_SIZE) do |operation|
      dispatch(operation)
    rescue StandardError => e
      # Un fallo al despachar una operación no debe frenar al resto del lote.
      Rails.logger.error(
        "[Jabvox::Drive::PendingOperationRetryJob] op=#{operation.id} kind=#{operation.kind} " \
        "dispatch falló: #{e.class} - #{e.message}"
      )
    end
  end

  private

  def dispatch(operation)
    case operation.kind.to_s
    when 'ingest_attachment'
      # Camino genérico: adjunto entrante de CUALQUIER bandeja (copia el blob de
      # Active Storage al Drive). Es el camino principal de ingesta.
      Jabvox::Drive::AttachmentIngestJob.perform_later(operation.account_id, operation.payload['attachment_id'])
    when 'ingest_media'
      # Camino específico de WhatsApp vía media_id (re-descarga de Meta). Opcional.
      Jabvox::Drive::MediaIngestJob.perform_later(operation.account_id, operation.id)
    when 'move_to_primary', 'reconcile'
      # Regularización de cuota / reconciliación: mueve objetos de overflow a
      # principal cuando hay espacio y recalcula contadores. Lo ejecuta
      # ReconciliationService (lo crea otro agente); aquí solo se dispara.
      Jabvox::Drive::QuotaRegularizationJob.perform_later(operation.account_id)
    when 'delete_object'
      delete_object(operation)
    else
      Rails.logger.warn("[Jabvox::Drive::PendingOperationRetryJob] kind desconocido: #{operation.kind} (op=#{operation.id})")
      operation.schedule_retry!("kind desconocido: #{operation.kind}")
    end
  end

  # Borrado durable de un objeto en MinIO. El payload lleva object_key y bucket.
  # Si MinIO está caído, dejamos pending para reintentar (no se pierde el borrado).
  def delete_object(operation)
    account = Account.find_by(id: operation.account_id)
    return operation.mark_completed! if account.nil?

    payload = operation.payload.to_h.with_indifferent_access
    object_key = payload[:object_key].presence
    return operation.mark_completed! if object_key.blank?

    storage = Jabvox::Drive::StorageService.new(account)
    bucket = overflow_bucket?(payload) ? Jabvox::Drive::StorageService::OVERFLOW : Jabvox::Drive::StorageService::PRIMARY
    storage.delete(object_key, bucket: bucket)
    operation.mark_completed!
  rescue Jabvox::Drive::StorageService::StorageUnavailableError => e
    operation.schedule_retry!("MinIO no disponible al borrar: #{e.message}")
  rescue Jabvox::Drive::StorageService::InvalidKeyError => e
    # Clave fuera del ámbito de la cuenta: no reintentable, dejar failed.
    operation.update!(status: :failed, last_error: e.message.first(2000), next_attempt_at: nil)
  end

  def overflow_bucket?(payload)
    payload[:bucket].presence == JabvoxDriveFile::BUCKET_OVERFLOW
  end
end
