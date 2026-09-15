module Enterprise::Concerns::Attachment
  extend ActiveSupport::Concern

  included do
    # La transcripción ya NO es automática: el agente la pide a demanda (botón "Ver
    # traducción" bajo el audio, ver AudioChip.vue), que dispara
    # Messages::AudioTranscriptionJob explícitamente vía el endpoint
    # POST .../messages/:id/transcribe. Se transcribe una sola vez — el resultado queda
    # en attachment.meta['transcribed_text'] y cualquier otro agente que abra la
    # conversación ya lo ve, sin volver a gastar la IA.
    #
    # Broadcast the message update so the FE bubble picks up the new audio
    # attachment immediately. Without this, the FE has to wait until Whisper
    # finishes (or fall back to a page refresh) — and if Whisper returns blank,
    # the bubble never gets the audio at all.
    after_create_commit :broadcast_message_update_for_audio
  end

  private

  def broadcast_message_update_for_audio
    return unless file_type.to_sym == :audio
    return unless message
    # Without an attached file, the message serializer's audio_metadata path
    # dereferences `file.metadata[:width]` on nil and raises. The pre-attach
    # broadcast wouldn't carry useful audio info anyway — skip until upload completes.
    return unless file.attached?

    message.reload.send_update_event
  end
end
