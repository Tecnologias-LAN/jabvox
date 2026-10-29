# frozen_string_literal: true

# Engancha el Drive a los adjuntos de CUALQUIER bandeja conectada (WhatsApp, email,
# Instagram, Telegram, SMS, web widget, etc.), no solo WhatsApp. Es ADITIVO: el
# flujo normal de adjuntos de Chatwoot queda intacto; esto solo registra —detrás del
# feature flag `jabvox_drive`— una operación durable para copiar el adjunto al Drive.
#
# Por qué a nivel de Attachment y no de cada canal: todos los canales terminan
# creando un Attachment con `has_one_attached :file` (Active Storage). Enganchando
# aquí cubrimos todas las bandejas de una vez y con una sola fuente de verdad.
#
# El job copia el BLOB ya almacenado por Active Storage al Drive (no re-descarga de
# la API del canal), así que funciona aunque el medio no tenga un media_id de Meta.
module Jabvox
  module AttachmentDriveIngest
    extend ActiveSupport::Concern

    # Tipos que tienen archivo real y vale la pena guardar en el Drive.
    DRIVE_FILE_TYPES = %w[image audio video file].freeze

    included do
      after_create_commit :enqueue_jabvox_drive_ingest, if: :jabvox_drive_ingestable?
    end

    private

    def jabvox_drive_ingestable?
      return false unless DRIVE_FILE_TYPES.include?(file_type.to_s)
      return false unless account&.feature_enabled?('jabvox_drive')

      # Solo adjuntos ENTRANTES (de un contacto). Los salientes del agente ya los
      # sube el propio agente al Drive por la UI si lo desea.
      message&.incoming?
    rescue StandardError => e
      # Nunca romper la creación del adjunto por el enganche del Drive.
      Rails.logger.warn("[jabvox-drive] ingestable? error attachment=#{id}: #{e.class}")
      false
    end

    def enqueue_jabvox_drive_ingest
      JabvoxDrivePendingOperation.enqueue(
        account: account,
        kind: 'ingest_attachment',
        idempotency_key: "attachment-#{id}",
        payload: jabvox_drive_ingest_payload
      )
      Jabvox::Drive::AttachmentIngestJob.perform_later(account.id, id)
    rescue StandardError => e
      # Si el registro falla, no rompemos el mensaje entrante; el scheduler de la
      # cola durable lo recuperará si la operación llegó a crearse.
      Rails.logger.warn("[jabvox-drive] enqueue ingest error attachment=#{id}: #{e.class}")
    end

    def jabvox_drive_ingest_payload
      {
        attachment_id: id,
        message_id: message_id,
        conversation_id: message&.conversation_id,
        contact_id: message&.conversation&.contact_id,
        file_type: file_type,
        filename: file.attached? ? file.filename.to_s : fallback_title.to_s
      }
    end
  end
end
