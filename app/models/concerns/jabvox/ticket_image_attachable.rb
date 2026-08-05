# Adjuntos de tickets: SOLO imágenes, con tope de tamaño. Se guardan en el mismo
# servicio de ActiveStorage que los adjuntos de las bandejas (config.active_storage.service),
# por lo que quedan junto a ellos en disco/bucket. Reutilizable por el ticket y por
# sus comentarios.
module Jabvox::TicketImageAttachable
  extend ActiveSupport::Concern

  MAX_IMAGE_BYTES = 15.megabytes
  ALLOWED_IMAGE_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze

  included do
    has_many_attached :attachments
    validate :attachments_are_images
  end

  private

  def attachments_are_images
    attachments.each do |attachment|
      next unless attachment.new_record?

      validate_image_size(attachment)
      validate_image_type(attachment)
    end
  end

  def validate_image_size(attachment)
    return if attachment.blob.byte_size <= MAX_IMAGE_BYTES

    errors.add(:attachments, "excede el tamaño máximo de #{MAX_IMAGE_BYTES / 1.megabyte} MB")
  end

  def validate_image_type(attachment)
    return if ALLOWED_IMAGE_TYPES.include?(attachment.blob.content_type)

    errors.add(:attachments, 'solo se permiten imágenes (PNG, JPG, GIF o WebP)')
  end
end
