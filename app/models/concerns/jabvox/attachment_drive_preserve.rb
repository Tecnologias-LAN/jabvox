# frozen_string_literal: true

# Preserva en el Drive los adjuntos cuyo mensaje/conversación se borra.
#
# El Drive "indexa, no copia": la fila JabvoxDriveFile apunta al MISMO objeto físico
# en MinIO que el blob de Active Storage del adjunto (una sola copia). Por defecto, al
# destruir el Attachment, Active Storage PURGA ese blob (borra el objeto de MinIO) —
# y entonces el Drive queda apuntando a un objeto inexistente (descargas con 503/404).
#
# Regla de negocio (confirmada): al borrar una conversación se eliminan la conversación
# y sus mensajes, pero NO los adjuntos que ya viven en el Drive. Por eso, si el objeto
# del blob está indexado por el Drive, aquí se DESVINCULA el blob del adjunto SIN
# purgarlo: se borra solo la fila de enlace (ActiveStorage::Attachment) con delete, que
# no dispara la purga. El objeto permanece en MinIO y el Drive lo sigue sirviendo.
#
# Es ADITIVO y a prueba de fallos: cualquier error aquí se traga (rescue) para no
# impedir el borrado del adjunto/mensaje.
module Jabvox::AttachmentDrivePreserve
  extend ActiveSupport::Concern

  included do
    # Debe correr ANTES de que Active Storage encole la purga del blob dependiente.
    before_destroy :jabvox_drive_detach_indexed_blob, prepend: true
  end

  private

  def jabvox_drive_detach_indexed_blob
    return unless jabvox_drive_blob_indexed?

    # Desvincula el blob del adjunto SIN purgarlo: borra solo la fila de enlace.
    # `delete` no corre callbacks → no se encola ActiveStorage::PurgeJob → el objeto
    # sobrevive en MinIO para el Drive. El blob huérfano no lo borra nadie porque el
    # Drive es ahora su único dueño lógico.
    file.attachment&.delete
  rescue StandardError => e
    Rails.logger.warn("[jabvox-drive] preserve detach error attachment=#{id}: #{e.class}")
    nil
  end

  # ¿El Drive referencia el mismo objeto físico que el blob de este adjunto (no purgado)?
  def jabvox_drive_blob_indexed?
    return false unless file.attached?
    return false unless account&.feature_enabled?('jabvox_drive')

    key = file.blob&.key
    return false if key.blank?

    account.jabvox_drive_files.exists?(object_key: key, purged_at: nil)
  end
end
