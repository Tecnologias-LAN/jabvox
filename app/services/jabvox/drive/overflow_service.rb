# frozen_string_literal: true

# Decide dónde aterriza un archivo entrante del Drive según la CUOTA de la cuenta.
#
# Flujo (ver QuotaService): se calcula el sha256 del contenido para deduplicar y
# para reservar/contar el tamaño exacto; luego:
#
#   1. Si ya existe una fila (account_id, sha256) -> se REUTILIZA (no re-sube ni
#      doble-cuenta). Idempotencia fuerte: dos ingestas del mismo adjunto comparten
#      la misma fila física.
#   2. Si `reserve!(bytes)` entra -> sube al bucket PRINCIPAL, crea la fila
#      status:available y `commit!`.
#   3. Si no cabe -> desvía a OVERFLOW: sube al bucket de excedentes, crea la fila
#      status:restricted bucket:overflow y `add_overflow!`. Se registra un WARN con
#      account_id (SIN datos sensibles) para alertar de cuota llena.
#
# Si MinIO está caído (StorageUnavailableError) se PROPAGA: el llamador (p. ej. la
# ingesta de WhatsApp) encola una JabvoxDrivePendingOperation y reintenta.
class Jabvox::Drive::OverflowService
  class FileTooLargeError < StandardError; end

  attr_reader :account

  def initialize(account)
    raise ArgumentError, 'account requerido' if account.nil?

    @account = account
  end

  # Tamaño máximo por archivo entrante (bytes). 0 = sin límite.
  def self.max_file_bytes
    ENV.fetch('JABVOX_DRIVE_MAX_FILE_MB', '200').to_i.megabytes
  end

  # Ingesta un archivo entrante. Devuelve el JabvoxDriveFile (nuevo o reutilizado).
  #
  # Parámetros:
  #   filename:     nombre original (se guarda tal cual; la object_key NO depende de él).
  #   content_type: MIME declarado.
  #   io/bytes:     el contenido (IO con #read o String de bytes). Uno de los dos.
  #   contact/message/conversation/created_by: referencias opcionales de origen.
  #   folder:       carpeta destino (si no, nil = raíz lógica de la cuenta).
  def ingest!(filename:, content_type: nil, io: nil, bytes: nil, contact: nil,
              message: nil, conversation: nil, created_by: nil, folder: nil)
    data = extract_data(io, bytes)
    size = data.bytesize
    validate_size!(size)
    sha = Digest::SHA256.hexdigest(data)
    # MIME REAL por magic bytes (no se confía en el content_type declarado por el
    # remitente/canal). Evita que un ejecutable se haga pasar por imagen, etc.
    real_mime = detect_mime(data, filename, content_type)

    existing = account.jabvox_drive_files.kept.find_by(sha256: sha)
    return existing if existing

    store(data: data, sha: sha, size: size, filename: filename, content_type: real_mime,
          contact: contact, message: message, conversation: conversation,
          created_by: created_by, folder: folder)
  rescue ActiveRecord::RecordNotUnique
    # Carrera de deduplicación: otra ingesta concurrente del mismo contenido ya
    # creó la fila (mismo object_key = acct/sha). Devolvemos la existente en vez
    # de un error; la reserva de esta ya se liberó en el rescue de upload_to_*.
    account.jabvox_drive_files.find_by(sha256: sha)
  end

  # INDEXA un objeto que YA vive en MinIO (p. ej. el blob de Active Storage de un
  # adjunto de mensaje, bajo acct-<id>/conversaciones/...) SIN re-subirlo: crea la
  # fila del Drive apuntando a esa misma object_key. Así el Drive lo ve, lo cuenta
  # en la cuota y lo sirve, con UNA sola copia física (cero duplicado en MinIO).
  #
  # object_key DEBE pertenecer a la cuenta (prefijo acct-<id>/) — se valida.
  # Si la cuota está llena, la fila se marca restricted y cuenta como overflow
  # (misma semántica que la ingesta normal), pero el objeto NO se mueve de sitio.
  def index_blob!(object_key:, filename:, content_type:, byte_size:, sha256: nil,
                  contact: nil, message: nil, conversation: nil, folder: nil)
    storage.assert_owned!(object_key) # barrera: solo keys de esta cuenta

    # Dedup por object_key (una referencia por objeto físico por cuenta).
    existing = account.jabvox_drive_files.kept.find_by(object_key: object_key)
    return existing if existing

    size = byte_size.to_i
    fits = quota.reserve!(size)
    file = build_file(
      filename: filename, content_type: content_type, size: size, sha: sha256,
      object_key: object_key, bucket: JabvoxDriveFile::BUCKET_PRIMARY,
      status: fits ? :available : :restricted,
      contact: contact, message: message, conversation: conversation,
      created_by: nil, folder: folder
    )
    file.save!
    settle_indexed_quota(file, size, fits: fits)
    file
  rescue ActiveRecord::RecordNotUnique
    account.jabvox_drive_files.find_by(object_key: object_key)
  end

  private

  # Ajusta los contadores tras indexar: si cabía, confirma el uso; si no, el objeto
  # queda restricted (en su sitio) y cuenta como overflow, con auditoría.
  def settle_indexed_quota(file, size, fits:)
    return quota.commit!(size) if fits

    quota.release!(size)
    quota.add_overflow!(size)
    Jabvox::Drive::AuditService.new(account).log(action: 'overflow', actor: nil, auditable: file,
                                                 metadata: { filename: file.filename, bytes: size, indexed: true })
  end

  # Decide destino (principal si cabe, overflow si no) y persiste.
  def store(data:, sha:, size:, filename:, content_type:, contact:, message:,
            conversation:, created_by:, folder:)
    args = { filename: filename, content_type: content_type, data: data, sha: sha,
             size: size, contact: contact, message: message, conversation: conversation,
             created_by: created_by, folder: folder }
    quota.reserve!(size) ? upload_to_primary(**args) : upload_to_overflow(**args)
  end

  def quota
    @quota ||= Jabvox::Drive::QuotaService.new(account)
  end

  def storage
    @storage ||= Jabvox::Drive::StorageService.new(account)
  end

  def validate_size!(size)
    max = self.class.max_file_bytes
    return if max <= 0 || size <= max

    raise FileTooLargeError,
          "adjunto entrante supera el máximo (#{max / 1.megabyte} MB) account_id=#{account.id} bytes=#{size}"
  end

  # Detecta el MIME real por los magic bytes del contenido (Marcel, el mismo que
  # usa Active Storage). Cae al content_type declarado solo si Marcel no decide.
  def detect_mime(data, filename, declared)
    Marcel::MimeType.for(StringIO.new(data), name: filename.to_s, declared_type: declared)
  rescue StandardError
    declared.presence || 'application/octet-stream'
  end

  def extract_data(io, bytes)
    raw = if !bytes.nil?
            bytes
          elsif io.respond_to?(:read)
            io.read
          else
            io
          end
    raise ArgumentError, 'contenido vacío (io/bytes)' if raw.nil?

    raw.to_s
  end

  # Ruta relativa del objeto. No se basa en el filename del usuario (evita
  # colisiones y caracteres peligrosos): se usa el sha como nombre físico.
  def relative_key(sha)
    "files/#{sha[0, 2]}/#{sha}"
  end

  def upload_to_primary(filename:, content_type:, data:, sha:, size:, contact:,
                        message:, conversation:, created_by:, folder:)
    result = storage.put(relative_key(sha), data, content_type: content_type,
                                                  bucket: Jabvox::Drive::StorageService::PRIMARY)
    file = build_file(filename: filename, content_type: content_type, size: size,
                      sha: sha, object_key: result[:key], bucket: JabvoxDriveFile::BUCKET_PRIMARY,
                      status: :available, contact: contact, message: message,
                      conversation: conversation, created_by: created_by, folder: folder)
    file.save!
    quota.commit!(size)
    file
  rescue StandardError
    # Cualquier fallo tras reservar (MinIO caído, validación de la fila, etc.)
    # libera la reserva y re-propaga. Incluye StorageUnavailableError.
    quota.release!(size)
    raise
  end

  def upload_to_overflow(filename:, content_type:, data:, sha:, size:, contact:,
                         message:, conversation:, created_by:, folder:)
    result = storage.put(relative_key(sha), data, content_type: content_type,
                                                  bucket: Jabvox::Drive::StorageService::OVERFLOW)
    file = build_file(filename: filename, content_type: content_type, size: size,
                      sha: sha, object_key: result[:key], bucket: JabvoxDriveFile::BUCKET_OVERFLOW,
                      status: :restricted, contact: contact, message: message,
                      conversation: conversation, created_by: created_by, folder: folder)
    file.save!
    quota.add_overflow!(size)
    Rails.logger.warn(
      '[jabvox-drive] overflow: cuota llena, archivo desviado a excedentes ' \
      "account_id=#{account.id} bytes=#{size}"
    )
    Jabvox::Drive::AuditService.new(account).log(action: 'overflow', actor: created_by, auditable: file,
                                                 metadata: { filename: filename, bytes: size })
    file
  end

  def build_file(filename:, content_type:, size:, sha:, object_key:, bucket:, status:,
                 contact:, message:, conversation:, created_by:, folder:)
    resolved_folder = resolve_folder(folder, contact, conversation)
    account.jabvox_drive_files.new(
      filename: filename,
      content_type: content_type,
      byte_size: size,
      sha256: sha,
      object_key: object_key,
      bucket: bucket,
      status: status,
      folder: resolved_folder,
      contact: contact,
      message: message,
      conversation: conversation,
      created_by: created_by
    )
  end

  # Un adjunto de conversación vive en contactos/<contacto>/<bandeja>/. Un archivo
  # sin contacto (subida manual) va a la raíz lógica.
  def resolve_folder(folder, contact, conversation = nil)
    return folder if folder
    return nil if contact.nil?

    JabvoxDriveFolder.for_contact_inbox(account, contact, conversation&.inbox)
  end
end
