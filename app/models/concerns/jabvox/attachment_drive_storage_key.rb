# frozen_string_literal: true

# Organiza los adjuntos de mensajes en MinIO con una estructura legible y aislada
# por cuenta, en lugar de la key plana aleatoria de Active Storage:
#
#   acct-<account_id>/conversaciones/conversacion-<conversation_id>/<token><ext>
#
# Así cada empresa tiene su prefijo (aislamiento por cuenta reforzado por el
# backend) y los adjuntos quedan agrupados por conversación. Los archivos subidos
# MANUALMENTE al Drive usan otra ruta (acct-<id>/files/..., ver StorageService), de
# modo que "conversaciones/" y los archivos manuales no se mezclan.
#
# Es ADITIVO y seguro:
#   - Solo actúa detrás del feature flag `jabvox_drive` y cuando el servicio de
#     Active Storage es S3/MinIO (en disco local la key plana da igual).
#   - Solo reescribe la key de un blob NUEVO (aún no subido). Nunca toca blobs ya
#     almacenados (no rompe adjuntos históricos ni mueve objetos).
#   - Deriva la cuenta/conversación del PROPIO attachment (no de Current.account),
#     así funciona en webhooks entrantes y jobs async donde Current no está seteado.
#   - Si algo falla, cae al comportamiento por defecto (key plana): nunca rompe la
#     creación del adjunto ni la mensajería.
module Jabvox::AttachmentDriveStorageKey
  extend ActiveSupport::Concern

  included do
    # before_save (no after): la key debe quedar fijada ANTES de que Active Storage
    # suba el blob al servicio. En el guardado del attachment, el blob nuevo se
    # sube usando su key; si la reescribimos antes, el objeto va a la ruta correcta.
    before_save :assign_jabvox_drive_storage_key, if: :jabvox_drive_key_applicable?
  end

  private

  # Una cadena de guardas lineal y legible; la complejidad es inherente a verificar
  # todas las precondiciones de seguridad antes de reescribir la key.
  def jabvox_drive_key_applicable? # rubocop:disable Metrics/CyclomaticComplexity
    file.attached? &&
      jabvox_drive_new_blob? &&
      message&.conversation_id.present? &&
      account&.feature_enabled?('jabvox_drive') &&
      jabvox_drive_s3_service?
  rescue StandardError => e
    Rails.logger.warn("[jabvox-drive] storage_key applicable? attachment=#{id}: #{e.class}")
    false
  end

  # Blob NUEVO (aún no subido a MinIO): solo entonces reescribir la key es seguro.
  def jabvox_drive_new_blob?
    blob = file.blob
    blob.present? && blob.new_record?
  end

  def assign_jabvox_drive_storage_key
    blob = file.blob
    return if blob.nil?

    ext = File.extname(blob.filename.to_s)
    token = blob.key # token aleatorio ya generado por Active Storage
    blob.key = "#{jabvox_drive_contact_prefix}#{token}#{ext}"
  rescue StandardError => e
    # Ante cualquier problema, se deja la key por defecto (plana): el adjunto se
    # guarda igual, solo sin la estructura por contacto/bandeja.
    Rails.logger.warn("[jabvox-drive] assign storage_key attachment=#{id}: #{e.class}")
  end

  # acct-<id>/contactos/<nombre-telefono-username-id>/<bandeja>/
  def jabvox_drive_contact_prefix
    conversation = message.conversation
    rel = Jabvox::Drive::PathBuilder.relative_prefix(
      contact: conversation&.contact, inbox: conversation&.inbox
    )
    "acct-#{account_id}/#{rel}"
  end

  # ¿El servicio de Active Storage es S3/MinIO? En disco local la key plana es
  # irrelevante (y los paths con "/" se crean como subcarpetas igual, pero no
  # aporta y evitamos efectos raros). Gateado para actuar solo donde importa.
  def jabvox_drive_s3_service?
    file.blob&.service.is_a?(ActiveStorage::Service::S3Service)
  rescue StandardError
    false
  end
end
