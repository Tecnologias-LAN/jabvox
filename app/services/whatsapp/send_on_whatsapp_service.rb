class Whatsapp::SendOnWhatsappService < Base::SendOnChannelService
  private

  def channel_class
    Channel::Whatsapp
  end

  def perform_reply
    return send_template_message if template_params.present?
    return send_session_message if message.conversation.can_reply?

    message.update!(status: :failed, external_error: I18n.t('errors.whatsapp.message_outside_messaging_window'))
  end

  def send_template_message
    processor = Whatsapp::TemplateProcessorService.new(
      channel: channel,
      template_params: template_params,
      message: message
    )

    name, namespace, lang_code, processed_parameters = processor.call

    if name.blank?
      message.update!(status: :failed, external_error: 'Template not found or invalid template name')
      return
    end

    message_id = channel.send_template(message.conversation.contact_inbox.source_id, {
                                         name: name,
                                         namespace: namespace,
                                         lang_code: lang_code,
                                         parameters: processed_parameters
                                       }, message)
    message.update!(source_id: message_id) if message_id.present?

    # Muestra el media del header en la conversación de Jabvox (no solo el texto).
    attach_template_header_media(processor) if message_id.present?
  end

  # Si la plantilla tiene header de media (imagen/video/documento), descarga esa media y
  # la adjunta al mensaje para que se vea en Jabvox. Best-effort: nunca rompe el envío.
  def attach_template_header_media(processor)
    return if message.attachments.exists?

    media = processor.resolved_header_media
    return if media.blank?

    resolver = Whatsapp::TemplateMediaResolverService.new(
      channel: channel, media_url: media['media_url'], media_type: media['media_type'],
      template_name: template_params['name']
    )
    binary, content_type = resolver.fetch_binary
    return if binary.blank?

    attach_binary_to_message(binary, content_type, media['media_type'])
  rescue StandardError => e
    Rails.logger.warn "[WA SendTemplate] attach header media failed: #{e.message}"
  end

  def attach_binary_to_message(binary, content_type, media_type)
    ct = content_type.to_s.split(';').first.presence || 'image/jpeg'
    ext = { 'image/jpeg' => 'jpg', 'image/png' => 'png', 'video/mp4' => 'mp4', 'application/pdf' => 'pdf' }[ct] ||
          { 'image' => 'jpg', 'video' => 'mp4', 'document' => 'pdf' }[media_type.to_s] || 'jpg'
    # file_type de Attachment: image/video para media, file para documentos.
    file_type = case media_type.to_s
                when 'video' then 'video'
                when 'document' then 'file'
                else 'image'
                end

    attachment = message.attachments.build(account_id: message.account_id, file_type: file_type)
    attachment.file.attach(io: StringIO.new(binary), filename: "plantilla_header.#{ext}", content_type: ct)
    attachment.save!
  end

  def send_session_message
    message_id = channel.send_message(message.conversation.contact_inbox.source_id, message)
    message.update!(source_id: message_id) if message_id.present?
  end

  def template_params
    message.additional_attributes && message.additional_attributes['template_params']
  end
end
