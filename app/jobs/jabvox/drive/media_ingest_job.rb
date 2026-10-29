# frozen_string_literal: true

# Ingesta DURABLE de un medio entrante (WhatsApp) al Drive (MinIO).
#
# Este job es el consumidor de la cola durable `JabvoxDrivePendingOperation`
# (kind: ingest_media). El medio ya fue descargado por el pipeline legacy de
# WhatsApp y adjuntado al Message (ese flujo sigue intacto); este job AÑADE la
# copia canónica en el Drive, re-descargando el medio desde Meta por su media_id.
#
# Garantías:
#   - Idempotencia: si la operation ya está `completed` no hace nada; el lock por
#     idempotency_key evita que dos workers procesen el mismo medio a la vez; y la
#     actualización del Message no duplica adjuntos (se busca por media_id/sha256).
#   - Resiliencia: si MinIO está caído o la URL temporal de Meta expiró (404/401),
#     NO se pierde el trabajo: `schedule_retry!` lo deja `pending` con backoff. El
#     media_id se conserva en el payload para poder re-obtener la URL temporal.
#   - No re-raise de errores recuperables: así el trabajo no se "pierde" en la
#     cola de Sidekiq; la cola durable en Postgres es la fuente de reintentos.
#
# Seguridad (CLAUDE.md / skill jabvox-security):
#   - Nunca se loguea el token del canal, la URL firmada de Meta ni el contenido.
#   - La cuenta se resuelve por id y toda operación va scopeada a esa cuenta.
class Jabvox::Drive::MediaIngestJob < MutexApplicationJob
  include Jabvox::AccountFairShare

  queue_as :jabvox_drive

  # Si no se puede tomar el lock (otro worker procesando el mismo medio),
  # reintentamos unas pocas veces; al agotarse NO perdemos nada: la operation
  # sigue `pending` en Postgres y el scheduler la reencolará.
  retry_on LockAcquisitionError, wait: 5.seconds, attempts: 5

  # Fairness por cuenta (noisy neighbor): ver AttachmentIngestJob.
  fair_share_limit 3
  fair_share_env 'JABVOX_DRIVE_MAX_INFLIGHT_PER_ACCOUNT'

  # Errores recuperables que NO deben matar el trabajo: los traducimos a
  # schedule_retry! sobre la cola durable.
  class RecoverableError < StandardError; end
  # Error definitivo: el medio no existe / no se puede recuperar jamás.
  class PermanentError < StandardError; end

  def perform(account_id, pending_operation_id)
    @account = Account.find_by(id: account_id)
    return if @account.nil?

    @operation = @account.jabvox_drive_pending_operations.find_by(id: pending_operation_id)
    return if @operation.nil?
    return if @operation.completed? # idempotencia

    with_account_fair_share(account_id) do
      key = format(::Redis::Alfred::JABVOX_DRIVE_INGEST_MUTEX, idempotency_key: @operation.idempotency_key)
      with_lock(key, 60.seconds) do
        process_operation
      end
    end
  end

  private

  attr_reader :account, :operation

  def process_operation
    # Releer dentro del lock: otro worker pudo haberla completado.
    operation.reload
    return if operation.completed?

    operation.processing!
    ingest!
  rescue PermanentError => e
    # No recuperable: marcamos failed guardando el motivo (sin datos sensibles).
    mark_failed(e.message)
  rescue RecoverableError => e
    operation.schedule_retry!(e.message)
  rescue StandardError => e
    # Cualquier otro fallo (red, S3, timeout) es recuperable por defecto: NO
    # re-lanzamos para no perder el trabajo; la cola durable reintenta.
    operation.schedule_retry!("#{e.class}: #{e.message}")
  end

  def ingest!
    payload = operation.payload.to_h.with_indifferent_access
    media_id = payload[:media_id].presence
    raise PermanentError, 'media_id ausente en payload' if media_id.blank?

    storage = Jabvox::Drive::StorageService.new(account)
    # MinIO caído: no perdemos nada, dejamos pending y reintentamos luego.
    unless storage.available?
      operation.schedule_retry!('storage no disponible (MinIO)')
      return
    end

    inbox = resolve_inbox(payload)
    raise PermanentError, 'inbox/canal no encontrado para re-descarga' if inbox&.channel.nil?

    download = download_media(inbox.channel, media_id, payload)
    return if download.nil? # schedule_retry ya aplicado dentro

    drive_file = ingest_binary(payload, download)
    attach_to_message_idempotent(payload, drive_file, download)

    operation.mark_completed!
  end

  # Re-descarga el medio desde Meta reutilizando la lógica del canal:
  #   1) media_url(media_id) + api_headers -> URL temporal
  #   2) Down.download(url, headers) -> binario
  # Devuelve un hash con el binario o nil (y programa reintento) si la URL
  # temporal expiró / el token del canal está vencido.
  def download_media(channel, media_id, payload)
    url_response = HTTParty.get(channel.media_url(media_id), headers: channel.api_headers)

    if url_response.unauthorized?
      # Token del canal vencido: recuperable (se puede re-autorizar y reintentar).
      operation.schedule_retry!('canal no autorizado al pedir URL de medio (401)')
      return nil
    end

    unless url_response.success?
      # 404 u otro: la URL temporal del medio pudo expirar; reintentamos con el
      # media_id conservado. Si Meta ya purgó el medio, los reintentos agotarán
      # MAX_ATTEMPTS y la operation pasará a failed (no se bloquea la cola).
      operation.schedule_retry!("respuesta no exitosa al pedir URL de medio (#{url_response.code})")
      return nil
    end

    temp_url = url_response.parsed_response.is_a?(Hash) ? url_response.parsed_response['url'] : nil
    if temp_url.blank?
      operation.schedule_retry!('URL temporal de medio ausente en respuesta')
      return nil
    end

    build_download(channel, temp_url, payload)
  rescue Down::NotFound, Down::ClientError => e
    # La URL temporal expiró o el medio no está disponible ahora: recuperable.
    operation.schedule_retry!("descarga de medio falló (#{e.class})")
    nil
  end

  def build_download(channel, temp_url, payload)
    downloaded = Down.download(temp_url, headers: channel.api_headers)
    data = downloaded.read
    content_type = payload[:content_type].presence || downloaded.content_type
    filename = resolve_filename(payload, downloaded)
    downloaded.close if downloaded.respond_to?(:close)

    {
      data: data,
      content_type: content_type,
      filename: filename,
      sha256: Digest::SHA256.hexdigest(data),
      byte_size: data.bytesize
    }
  end

  # Entrega el binario al OverflowService, que decide principal vs overflow
  # según la cuota y crea/recupera el JabvoxDriveFile canónico. El propio servicio
  # calcula el sha256 y DEDUPLICA: si ya existe un file con ese sha devuelve el
  # existente, lo que da idempotencia natural a la reejecución de este job.
  def ingest_binary(payload, download)
    service = overflow_service
    raise RecoverableError, 'OverflowService no disponible todavía' if service.nil?

    # Firma real de Jabvox::Drive::OverflowService#ingest! (verificada): usa `bytes:`
    # (String de bytes) y calcula el sha256 internamente — por eso NO le pasamos
    # sha256:. Pasamos bytes en vez de io para no depender del estado del IO.
    service.ingest!(
      filename: download[:filename],
      content_type: download[:content_type],
      bytes: download[:data],
      contact: resolve_contact(payload),
      message: resolve_message(payload),
      conversation: resolve_conversation(payload)
    )
  end

  def overflow_service
    return nil unless defined?(Jabvox::Drive::OverflowService)

    Jabvox::Drive::OverflowService.new(account)
  end

  # Vincula el JabvoxDriveFile al Message de forma IDEMPOTENTE: no crea un
  # adjunto duplicado si ya hay uno para ese media_id/sha256. El pipeline legacy
  # ya creó el ActiveStorage attachment; aquí solo anotamos la referencia al
  # objeto del Drive en el metadata del drive_file sin tocar el adjunto existente.
  def attach_to_message_idempotent(payload, drive_file, download)
    return if drive_file.nil?
    return if resolve_message(payload).nil?

    # Anotamos en el drive_file la procedencia (media_id) para dedupe futuro.
    merged = (drive_file.metadata || {}).merge(
      'source' => 'whatsapp',
      'media_id' => payload[:media_id].to_s,
      'message_source_id' => payload[:message_source_id].to_s,
      'sha256' => download[:sha256]
    )
    drive_file.update!(metadata: merged) if drive_file.metadata != merged
  end

  # ---- resolución de asociaciones, siempre scopeada a la cuenta ----

  # Resolvemos el inbox (y de ahí el canal) siempre dentro de la cuenta. El
  # enganche de WhatsApp guarda inbox_id en el payload; channel_id queda como
  # respaldo (canal polimórfico Channel::Whatsapp).
  def resolve_inbox(payload)
    inbox_id = payload[:inbox_id].presence
    inbox = account.inboxes.find_by(id: inbox_id) if inbox_id
    return inbox if inbox

    channel_id = payload[:channel_id].presence
    return nil if channel_id.blank?

    account.inboxes.find_by(channel_type: 'Channel::Whatsapp', channel_id: channel_id)
  end

  def resolve_contact(payload)
    id = payload[:contact_id].presence
    id && account.contacts.find_by(id: id)
  end

  def resolve_message(payload)
    id = payload[:message_id].presence
    id && account.messages.find_by(id: id)
  end

  def resolve_conversation(payload)
    id = payload[:conversation_id].presence
    id && account.conversations.find_by(id: id)
  end

  def resolve_filename(payload, downloaded)
    payload[:filename].presence ||
      (downloaded.respond_to?(:original_filename) ? downloaded.original_filename : nil) ||
      "wa-#{payload[:media_id]}"
  end

  def mark_failed(message)
    operation.update!(status: :failed, last_error: message.to_s.first(2000), next_attempt_at: nil)
  end
end
