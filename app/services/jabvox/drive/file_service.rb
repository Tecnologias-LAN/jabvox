# frozen_string_literal: true

# CRUD de archivos del Drive para subidas INTERACTIVAS (desde el dashboard).
#
# A diferencia de la ingesta entrante (OverflowService, que desvía a excedentes
# cuando la cuota está llena), una subida manual que no cabe se RECHAZA: el agente
# debe liberar espacio o ampliar el plan. Por eso aquí se exige `reserve!` y, si
# no entra, se lanza QuotaExceededError.
#
# Validaciones: tamaño máximo (ENV JABVOX_DRIVE_MAX_FILE_MB, default 200) y nombre
# seguro. El contenido se deduplica por sha256 (misma fila por account+sha).
class Jabvox::Drive::FileService
  class Error < StandardError; end
  class QuotaExceededError < Error; end
  class FileTooLargeError < Error; end

  attr_reader :account

  def initialize(account)
    raise ArgumentError, 'account requerido' if account.nil?

    @account = account
  end

  def self.max_file_bytes
    ENV.fetch('JABVOX_DRIVE_MAX_FILE_MB', '200').to_i.megabytes
  end

  # Tamaño máximo legible para mensajes (GB si es múltiplo de 1024 MB, si no MB).
  def self.human_max_size
    mb = max_file_bytes / 1.megabyte
    mb >= 1024 && (mb % 1024).zero? ? "#{mb / 1024} GB" : "#{mb} MB"
  end

  # Sube un archivo desde el dashboard. Devuelve el JabvoxDriveFile.
  # `upload` puede ser un ActionDispatch::Http::UploadedFile o cualquier objeto
  # con #read / #original_filename / #content_type. También acepta bytes sueltos.
  def upload!(upload: nil, bytes: nil, filename: nil, content_type: nil,
              folder_id: nil, contact_id: nil, created_by: nil)
    # Validar el tamaño ANTES de leer todo en memoria (anti-DoS/OOM del proceso web):
    # si el upload expone #size, se rechaza sin cargar el archivo.
    validate_size!(upload.size) if upload.respond_to?(:size) && upload.size

    data = read_upload(upload, bytes)
    name = safe_name(filename || upload&.try(:original_filename) || 'archivo')
    mime = resolve_mime(content_type || upload&.try(:content_type), data, name)

    validate_size!(data.bytesize)

    sha = Digest::SHA256.hexdigest(data)
    existing = account.jabvox_drive_files.kept.find_by(sha256: sha)
    return reuse_existing(existing, name, folder_id, contact_id, created_by) if existing

    folder = resolve_folder(folder_id, contact_id)
    contact = resolve_contact(contact_id)

    size = data.bytesize
    raise QuotaExceededError, 'cuota de almacenamiento agotada' unless quota.reserve!(size)

    store_and_persist(data: data, name: name, mime: mime, sha: sha, size: size,
                      folder: folder, contact: contact, created_by: created_by)
  rescue ActiveRecord::RecordNotUnique
    # Carrera de deduplicación: otra subida concurrente del mismo contenido ganó.
    # Devolvemos la fila existente (la reserva de esta ya se liberó en store_and_persist).
    account.jabvox_drive_files.kept.find_by(sha256: sha) ||
      account.jabvox_drive_files.find_by(sha256: sha)
  end

  def rename!(file, filename:)
    file.update!(filename: safe_name(filename))
    file
  end

  # Mueve el archivo a otra carpeta de la MISMA cuenta.
  def move!(file, folder_id:)
    folder = resolve_folder(folder_id, nil)
    file.update!(folder: folder)
    file
  end

  # Borrado lógico + borrado del objeto físico + descuento de cuota.
  # Solo descuenta used si el archivo estaba en el bucket principal y disponible.
  # Enviar a la PAPELERA (reversible). NO libera cuota ni borra el objeto físico:
  # el archivo sigue ocupando espacio hasta que se purgue (manual o a los 7 días).
  # Así nada se pierde por un borrado accidental.
  def destroy!(file, actor: nil)
    file.trash!(actor)
    true
  end

  # RESTAURAR desde la papelera (vuelve a estar activo y visible).
  def restore!(file)
    file.restore!
    file
  end

  # ELIMINAR DEFINITIVAMENTE (desde la papelera): borra el objeto físico de MinIO,
  # libera la cuota y marca purgado. ESTE es el único punto que libera espacio.
  # Idempotente: si ya estaba purgado, no hace nada.
  def purge!(file, actor: nil)
    return file if file.purged?

    counts_against_quota = !file.overflow? && !file.pending?
    bucket = file.overflow? ? Jabvox::Drive::StorageService::OVERFLOW : Jabvox::Drive::StorageService::PRIMARY
    size = file.byte_size.to_i

    # Solo borra el objeto físico si NINGUNA otra fila NO-purgada comparte el sha.
    delete_physical_object(file, bucket) unless shared_object?(file)

    file.mark_purged!(actor)
    if counts_against_quota
      quota.decrement_used!(size)
      # Al LIBERAR espacio del principal, promueve los excedentes (overflow) que ya quepan.
      enqueue_regularization_if_overflow
    elsif file.overflow?
      quota.remove_overflow!(size)
    end
    file
  end

  private

  def quota
    @quota ||= Jabvox::Drive::QuotaService.new(account)
  end

  def storage
    @storage ||= Jabvox::Drive::StorageService.new(account)
  end

  def read_upload(upload, bytes)
    raw = if !bytes.nil?
            bytes
          elsif upload.respond_to?(:read)
            upload.read
          else
            upload
          end
    raise Error, 'archivo vacío' if raw.nil?

    raw.to_s
  end

  def validate_size!(size)
    max = self.class.max_file_bytes
    return if max <= 0 || size <= max

    raise FileTooLargeError, "El archivo supera el máximo permitido. Solo se aceptan archivos de hasta #{self.class.human_max_size} por archivo."
  end

  def relative_key(sha)
    "files/#{sha[0, 2]}/#{sha}"
  end

  # Resuelve el MIME real. Prioridad:
  #   1) content_type explícito (del navegador/llamador), si es útil.
  #   2) detección por magic bytes (Marcel), usando el nombre como pista.
  # Así, aunque un adjunto llegue sin content_type, la vista previa del Drive
  # (que lo usa para decidir cómo abrir el archivo) nunca se queda sin tipo.
  def resolve_mime(given, data, name)
    given = given.to_s.strip
    return given if given.present? && given != 'application/octet-stream'

    detected = Marcel::MimeType.for(StringIO.new(data), name: name, declared_type: given.presence)
    detected.presence || given.presence || 'application/octet-stream'
  rescue StandardError
    given.presence || 'application/octet-stream'
  end

  def store_and_persist(data:, name:, mime:, sha:, size:, folder:, contact:, created_by:)
    result = storage.put(relative_key(sha), data, content_type: mime,
                                                  bucket: Jabvox::Drive::StorageService::PRIMARY)
    file = account.jabvox_drive_files.create!(
      filename: name,
      content_type: mime,
      byte_size: size,
      sha256: sha,
      object_key: result[:key],
      bucket: JabvoxDriveFile::BUCKET_PRIMARY,
      status: :available,
      folder: folder,
      contact: contact,
      created_by: created_by
    )
    quota.commit!(size)
    file
  rescue StandardError
    quota.release!(size)
    raise
  end

  # Reutiliza una fila existente (dedup). Si tenía carpeta/contacto distintos,
  # no se pisan: la primera referencia manda. Devuelve la fila tal cual.
  def reuse_existing(existing, _name, _folder_id, _contact_id, _created_by)
    existing
  end

  # ¿Otra fila NO purgada (activa o en papelera) comparte el mismo objeto físico?
  # Si sí, no se puede borrar el objeto de MinIO al purgar esta. Solo cuando no queda
  # ninguna referencia viva se elimina el objeto.
  def shared_object?(file)
    account.jabvox_drive_files.occupying_quota.where(sha256: file.sha256)
           .where.not(id: file.id).exists?
  end

  # Si hay archivos retenidos en overflow, encola la regularización (idempotente):
  # mueve a principal los que ya quepan tras liberar espacio. Solo encola si hay
  # algo que promover, para no disparar jobs en vano con 1000+ cuentas.
  def enqueue_regularization_if_overflow
    return unless account.jabvox_drive_files.kept
                         .exists?(bucket: JabvoxDriveFile::BUCKET_OVERFLOW)

    Jabvox::Drive::QuotaRegularizationJob.perform_later(account.id)
  rescue StandardError => e
    Rails.logger.error('[jabvox-drive] no se pudo encolar regularización tras borrado ' \
                       "account_id=#{account.id}: #{e.class}")
  end

  def delete_physical_object(file, bucket)
    storage.delete(file.object_key, bucket: bucket)
  rescue Jabvox::Drive::StorageService::StorageUnavailableError
    # Si MinIO está caído NO dejamos el objeto huérfano: encolamos un borrado
    # DURABLE que el scheduler reintentará cuando MinIO vuelva. El borrado lógico
    # no se bloquea, para no dejar al usuario atascado.
    JabvoxDrivePendingOperation.enqueue(
      account: account, kind: 'delete_object',
      idempotency_key: "delete-#{file.object_key}",
      payload: { object_key: file.object_key, bucket: bucket }
    )
    Rails.logger.warn('[jabvox-drive] delete: storage no disponible, borrado encolado ' \
                      "account_id=#{account.id} file_id=#{file.id}")
  end

  def resolve_folder(folder_id, contact_id)
    contact = resolve_contact(contact_id)
    return JabvoxDriveFolder.for_contact(account, contact) if contact && folder_id.blank?
    return nil if folder_id.blank?

    account.jabvox_drive_folders.find(folder_id)
  end

  def resolve_contact(contact_id)
    return nil if contact_id.blank?

    account.contacts.find(contact_id)
  end

  def safe_name(name)
    clean = File.basename(name.to_s).tr("\u0000", '').strip
    clean = clean.gsub(%r{[/\\]}, '_')
    raise Error, 'nombre de archivo inválido' if clean.blank?

    clean.first(255)
  end
end
