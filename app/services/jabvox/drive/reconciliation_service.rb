# frozen_string_literal: true

# Reconciliación del Drive: dos operaciones idempotentes y reanudables.
#
# == regularize!(account) ==
# Se dispara al AMPLIAR la cuota (upgrade de plan). Recalcula contadores y, por
# cada archivo retenido en overflow que ya quepa en el principal, lo mueve:
#   copy overflow->primary  ->  VERIFICA destino (head)  ->  cambia status a
#   available + bucket primary  ->  borra el objeto en overflow  ->  mueve el
#   conteo overflow->used.
# Si MinIO se cae a mitad, cada archivo queda en un estado consistente y el
# siguiente pase retoma donde quedó (reanudable). No doble-cuenta.
#
# == reconcile!(account) ==
# Auditoría de integridad: filas sin objeto físico en MinIO se marcan
# quarantined; objetos en MinIO sin fila se registran (log) para revisión manual.
# Actualiza last_reconciled_at.
class Jabvox::Drive::ReconciliationService
  attr_reader :account

  def initialize(account)
    raise ArgumentError, 'account requerido' if account.nil?

    @account = account
  end

  # Regulariza los excedentes tras una ampliación de cuota. Idempotente.
  # Devuelve { promoted:, skipped:, failed: }.
  def regularize!
    quota.recalculate!
    promoted = 0
    skipped = 0
    failed = 0

    restricted_files.find_each do |file|
      case promote_file(file)
      when :promoted then promoted += 1
      when :skipped then skipped += 1
      else failed += 1
      end
    end

    quota.recalculate!
    { promoted: promoted, skipped: skipped, failed: failed }
  end

  # Audita filas vs objetos físicos. Devuelve { missing_objects:, orphan_objects: }.
  def reconcile!
    missing = mark_missing_objects
    orphans = log_orphan_objects
    quota.recalculate!
    quota.storage_account.update!(last_reconciled_at: Time.current)
    { missing_objects: missing, orphan_objects: orphans }
  end

  private

  def quota
    @quota ||= Jabvox::Drive::QuotaService.new(account)
  end

  def storage
    @storage ||= Jabvox::Drive::StorageService.new(account)
  end

  # Archivos retenidos candidatos a promoción:
  #   - COPIADOS: viven físicamente en el bucket overflow (bucket == overflow).
  #   - INDEXADOS: el objeto ya está en el bucket primary (acct/conversaciones/...)
  #     pero quedó restricted por cuota llena; NO hay copia que mover, solo cambiar
  #     el status cuando haya espacio.
  def restricted_files
    account.jabvox_drive_files.kept
           .where(bucket: JabvoxDriveFile::BUCKET_OVERFLOW)
           .or(account.jabvox_drive_files.kept
                      .where(bucket: JabvoxDriveFile::BUCKET_PRIMARY, status: :restricted))
  end

  # Promueve un excedente SOLO si ya cabe. Reanudable e idempotente.
  # Devuelve :promoted, :skipped (no cabe aún) o :failed.
  def promote_file(file)
    size = file.byte_size.to_i
    return :skipped unless quota.reserve!(size)

    # Indexado (objeto ya en primary): no hay copia física que mover; solo se
    # libera el status. Para los copiados en overflow sí se copia y verifica.
    if file.bucket == JabvoxDriveFile::BUCKET_PRIMARY
      promote_indexed(file, size)
    else
      promote_copied(file, size)
    end
  rescue Jabvox::Drive::StorageService::StorageUnavailableError => e
    # MinIO caído a mitad: libera la reserva y deja el archivo tal cual para
    # el próximo pase. No se pierde consistencia.
    release_and_fail(size, file, "storage no disponible err=#{e.class}")
  end

  # Excedente INDEXADO: el objeto ya está en su sitio (primary). Solo cambia el
  # status a available y mueve el conteo overflow->used.
  def promote_indexed(file, size)
    file.update!(status: :available)
    quota.commit!(size)
    quota.remove_overflow!(size)
    Jabvox::Drive::AuditService.new(account).log(action: 'promote', actor: nil, auditable: file,
                                                 metadata: { filename: file.filename, bytes: size, indexed: true })
    notify_chat_restored(file)
    :promoted
  end

  # Excedente COPIADO: mueve el objeto de overflow a primary, verifica y borra el
  # sobrante. object_key física no cambia entre buckets (mismo acct-<id>/files/..).
  def promote_copied(file, size)
    key = file.object_key
    return release_and_fail(size, file, 'copia no verificada') unless copy_and_verify(key)

    file.update!(bucket: JabvoxDriveFile::BUCKET_PRIMARY, status: :available)
    quota.commit!(size)
    quota.remove_overflow!(size)
    delete_overflow_copy(key)
    Jabvox::Drive::AuditService.new(account).log(action: 'promote', actor: nil, auditable: file,
                                                 metadata: { filename: file.filename, bytes: size })
    notify_chat_restored(file)
    :promoted
  end

  # Al promoverse un adjunto de mensaje (ya hay espacio), dispara message.updated
  # para que ActionCable reenvíe el push_event_data actualizado (sin storage_blocked)
  # y el chat muestre la imagen EN VIVO, sin recargar. Regla de oro: el payload de
  # ActionCable lleva account_id (lo incluye push_event_data / el listener). Nunca
  # rompe la promoción si el evento falla.
  def notify_chat_restored(file)
    message = file.message
    return if message.nil?

    Rails.configuration.dispatcher.dispatch(
      Events::Types::MESSAGE_UPDATED, Time.zone.now,
      message: message, performed_by: nil, previous_changes: {}
    )
  rescue StandardError => e
    Rails.logger.warn("[jabvox-drive] notify_chat_restored message=#{file.message_id}: #{e.class}")
  end

  # Copia overflow->primary y VERIFICA el destino con head. Devuelve true si ok.
  def copy_and_verify(key)
    storage.copy(key, key,
                 src_bucket: Jabvox::Drive::StorageService::OVERFLOW,
                 dst_bucket: Jabvox::Drive::StorageService::PRIMARY)
    !storage.head(key, bucket: Jabvox::Drive::StorageService::PRIMARY).nil?
  end

  def release_and_fail(size, file, reason)
    quota.release!(size)
    Rails.logger.warn("[jabvox-drive] regularize: #{reason} account_id=#{account.id} file_id=#{file.id}")
    :failed
  end

  def delete_overflow_copy(key)
    storage.delete(key, bucket: Jabvox::Drive::StorageService::OVERFLOW)
  rescue Jabvox::Drive::StorageService::StorageUnavailableError => e
    # El archivo ya está promovido y contado; una copia huérfana en overflow
    # no rompe la cuota (recalculate! cuenta por bucket de la FILA). La barre
    # el siguiente reconcile!.
    Rails.logger.warn("[jabvox-drive] regularize: no se pudo borrar copia overflow account_id=#{account.id} err=#{e.class}")
  end

  # Marca quarantined las filas cuyo objeto ya no existe en MinIO.
  def mark_missing_objects
    count = 0
    account.jabvox_drive_files.kept.where.not(status: :pending).find_each do |file|
      bucket = file.overflow? ? Jabvox::Drive::StorageService::OVERFLOW : Jabvox::Drive::StorageService::PRIMARY
      next if storage.head(file.object_key, bucket: bucket)

      file.update!(status: :quarantined) unless file.quarantined?
      count += 1
    rescue Jabvox::Drive::StorageService::StorageUnavailableError
      # Sin acceso a MinIO no se puede afirmar que falte: se omite este pase.
      next
    end
    count
  end

  # Detecta objetos físicos sin fila (solo log; no se borran automáticamente).
  def log_orphan_objects
    known_keys = account.jabvox_drive_files.pluck(:object_key).to_set
    orphans = 0
    [Jabvox::Drive::StorageService::PRIMARY, Jabvox::Drive::StorageService::OVERFLOW].each do |bucket|
      storage.list('', bucket: bucket).each do |obj|
        next if known_keys.include?(obj[:key])

        orphans += 1
        Rails.logger.warn("[jabvox-drive] reconcile: objeto huérfano en MinIO account_id=#{account.id} bucket=#{bucket}")
      end
    rescue Jabvox::Drive::StorageService::StorageUnavailableError
      next
    end
    orphans
  end
end
