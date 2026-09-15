class Messages::AudioTranscriptionJob < ApplicationJob
  # Cola AISLADA y dedicada: transcribir audio llama a un proveedor de IA externo y puede
  # tardar varios segundos por archivo — vive en su propio worker Sidekiq para que no
  # pueda taponar el envío/recepción de mensajes ni ningún otro servicio.
  queue_as :jabvox_transcription

  discard_on Faraday::BadRequestError do |job, error|
    log_context = {
      attachment_id: job.arguments.first,
      job_id: job.job_id,
      status_code: error.response&.dig(:status)
    }

    Rails.logger.warn("Discarding audio transcription job due to bad request: #{log_context}")
  end
  retry_on ActiveStorage::FileNotFoundError, wait: 2.seconds, attempts: 3

  def perform(attachment_id)
    attachment = Attachment.find_by(id: attachment_id)
    return if attachment.blank?

    Messages::AudioTranscriptionService.new(attachment).perform
  end
end
