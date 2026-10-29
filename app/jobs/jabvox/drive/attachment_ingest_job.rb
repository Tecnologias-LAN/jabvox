# frozen_string_literal: true

# Copia al Drive (MinIO) un adjunto entrante de CUALQUIER bandeja conectada.
#
# A diferencia de MediaIngestJob (que re-descarga de la API de Meta por media_id),
# este job toma el BLOB ya almacenado por Active Storage y lo copia al Drive. Así
# cubre todos los canales (email, Instagram, Telegram, SMS, web widget, WhatsApp…),
# porque todos crean un Attachment con `has_one_attached :file`.
#
# Garantías:
#   - Idempotencia: la operación es idempotente por attachment-<id>; OverflowService
#     deduplica por sha256; si ya se ingirió, no re-sube ni doble-cuenta.
#   - Resiliencia: si MinIO está caído, schedule_retry! deja la operación pending con
#     backoff; el adjunto no se pierde (el blob sigue en Active Storage).
#   - No re-raise de errores recuperables: la cola durable en Postgres reintenta.
class Jabvox::Drive::AttachmentIngestJob < MutexApplicationJob
  include Jabvox::AccountFairShare

  queue_as :jabvox_drive

  retry_on LockAcquisitionError, wait: 5.seconds, attempts: 5

  # Fairness: una cuenta con miles de adjuntos no puede acaparar los hilos del worker
  # dedicado y ahogar la ingesta de las demás (noisy neighbor). Los que exceden el
  # cupo se re-encolan con delay; el job es idempotente, así que reintentar es seguro.
  fair_share_limit 3
  fair_share_env 'JABVOX_DRIVE_MAX_INFLIGHT_PER_ACCOUNT'

  def perform(account_id, attachment_id)
    account = Account.find_by(id: account_id)
    return if account.nil?

    operation = account.jabvox_drive_pending_operations
                       .find_by(idempotency_key: "attachment-#{attachment_id}")
    return if operation&.completed?

    with_account_fair_share(account_id) do
      key = format(::Redis::Alfred::JABVOX_DRIVE_INGEST_MUTEX, idempotency_key: "attachment-#{attachment_id}")
      with_lock(key, 60.seconds) do
        ingest(account, attachment_id, operation)
      end
    end
  end

  private

  def ingest(account, attachment_id, operation)
    operation&.processing!
    # Attachment tiene columna account_id propia; se scopea por cuenta sin confiar
    # en el id suelto (aislamiento: solo adjuntos de ESTA cuenta).
    attachment = Attachment.where(account_id: account.id).find_by(id: attachment_id)
    # El adjunto pudo borrarse entre el encolado y el proceso: no es un error.
    return operation&.mark_completed! if attachment.nil? || !attachment.file.attached?

    unless Jabvox::Drive::StorageService.new(account).available?
      operation&.schedule_retry!('storage no disponible (MinIO)')
      return
    end

    ingest_attachment(account, attachment)
    operation&.mark_completed!
  rescue Jabvox::Drive::OverflowService::FileTooLargeError => e
    # Permanente: reintentar no cambia el tamaño. Se marca failed (sin datos sensibles).
    operation&.update!(status: :failed, last_error: "archivo demasiado grande (#{e.class})")
  rescue Jabvox::Drive::StorageService::StorageUnavailableError => e
    operation&.schedule_retry!("storage error: #{e.class}")
  rescue StandardError => e
    # Recuperable por defecto: no perdemos el trabajo.
    operation&.schedule_retry!("#{e.class}: #{e.message}")
  end

  # Copia el blob al Drive usando streaming (blob.open) en vez de cargar el archivo
  # entero con .download (lineamiento Jabvox/AttachmentDownload).
  def ingest_attachment(account, attachment)
    blob = attachment.file.blob
    # Rechazar por tamaño ANTES de abrir/leer el blob (anti-OOM del worker compartido).
    max = Jabvox::Drive::OverflowService.max_file_bytes
    if max.positive? && blob.byte_size.to_i > max
      raise Jabvox::Drive::OverflowService::FileTooLargeError,
            "adjunto #{attachment.id} supera el máximo (#{max / 1.megabyte} MB)"
    end

    if blob_in_drive_bucket?(blob, account)
      index_attachment(account, attachment, blob) # mismo MinIO: 1 copia, solo indexar
    else
      copy_attachment(account, attachment) # disco local u otro servicio: copiar al Drive
    end
  end

  # El blob de Active Storage ya vive en el MISMO bucket MinIO del Drive y bajo el
  # prefijo de la cuenta (acct-<id>/...). Entonces NO se re-sube: el Drive indexa esa
  # misma object_key. Una sola copia física, cero duplicado.
  def index_attachment(account, attachment, blob)
    conversation = attachment.message&.conversation
    Jabvox::Drive::OverflowService.new(account).index_blob!(
      object_key: blob.key,
      filename: attachment.file.filename.to_s,
      content_type: attachment.file.content_type,
      byte_size: blob.byte_size,
      sha256: blob.checksum,
      contact: conversation&.contact,
      message: attachment.message,
      conversation: conversation
    )
  end

  # El blob está en disco local u otro servicio distinto al bucket del Drive: se copia
  # al Drive por streaming (blob.open) en vez de cargar todo con .download.
  def copy_attachment(account, attachment)
    conversation = attachment.message&.conversation
    attachment.file.blob.open do |io|
      Jabvox::Drive::OverflowService.new(account).ingest!(
        filename: attachment.file.filename.to_s,
        content_type: attachment.file.content_type,
        io: io,
        contact: conversation&.contact,
        message: attachment.message,
        conversation: conversation
      )
    end
  end

  # ¿El blob vive en el mismo bucket MinIO del Drive y bajo el prefijo de la cuenta?
  # Si sí, se puede indexar en vez de copiar. Conservador: ante la duda, copia.
  def blob_in_drive_bucket?(blob, account)
    return false unless blob.service.is_a?(ActiveStorage::Service::S3Service)

    same_bucket = blob.service.bucket.name.to_s == ENV.fetch('JABVOX_DRIVE_BUCKET', nil).to_s
    same_bucket && blob.key.to_s.start_with?("acct-#{account.id}/")
  rescue StandardError
    false
  end
end
