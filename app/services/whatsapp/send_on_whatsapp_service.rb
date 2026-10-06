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
    persist_flow_tokens!

    processor = Whatsapp::TemplateProcessorService.new(
      channel: channel,
      template_params: template_params,
      message: message
    )

    # OJO: processor.call sobreescribe su template_params interno con los componentes,
    # así que resolvemos el media del header ANTES de llamar a call.
    header_media = processor.resolved_header_media

    name, namespace, lang_code, processed_parameters = processor.call

    if name.blank?
      message.update!(status: :failed, external_error: 'Template not found or invalid template name')
      return
    end

    deliver_template(name, namespace, lang_code, processed_parameters, header_media)
  # Si algo revienta armando el payload (p. ej. falta "location" en una plantilla
  # con header LOCATION, o "cards" en un CAROUSEL), el mensaje ya existe con
  # status "sent" desde que se creó por la API — sin este rescue se queda así,
  # sin source_id y sin error, "cargando" para siempre en la conversación.
  # Confirmado en producción: msg #204 (diag_location sin processed_params.location)
  # quedó exactamente en ese estado porque ArgumentError subía sin capturarse.
  rescue StandardError => e
    Rails.logger.error "[WA SendTemplate] msg=#{message.id} template=#{template_params['name']}: #{e.class} #{e.message}"
    message.update!(status: :failed, external_error: e.message)
  end

  def deliver_template(name, namespace, lang_code, parameters, header_media)
    message_id = channel.send_template(message.conversation.contact_inbox.source_id, {
                                         name: name,
                                         namespace: namespace,
                                         lang_code: lang_code,
                                         parameters: parameters
                                       }, message)
    return if message_id.blank?

    message.update!(source_id: message_id)
    # Muestra el media del header en la conversación de Jabvox (no solo el texto).
    attach_template_header_media(header_media)
  end

  # Si la plantilla tiene header de media (imagen/video/documento), descarga esa media y
  # la adjunta al mensaje para que se vea en Jabvox. Best-effort: nunca rompe el envío.
  def attach_template_header_media(media)
    return if media.blank?
    return if message.attachments.exists?

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
  # El envío de plantillas ya estaba protegido; este camino no. Si reventaba armando el
  # payload o por un fallo de red, el mensaje se quedaba en "sent" sin source_id: el
  # relojito eterno en la conversación. Se marca fallido indicando que fue la app, no
  # WhatsApp, que es lo primero que hay que distinguir al revisar.
  rescue StandardError => e
    Rails.logger.error "[WA SendSession] msg=#{message.id}: #{e.class} #{e.message}"
    message.update!(status: :failed, external_error: "No se pudo enviar desde Jabvox: #{e.message}")
  end

  def template_params
    message.additional_attributes && message.additional_attributes['template_params']
  end

  # Asigna un flow_token a cada botón de formulario que no lo traiga y lo guarda
  # en el mensaje ANTES de armar el payload, que es lo que permite reconocer de
  # qué envío viene la respuesta cuando Meta la manda por el webhook (ver
  # Jabvox::BulkWhatsappFlowReply y SubmissionRecorder, que lo buscan aquí).
  # Generarlo más adelante lo enviaba a Meta sin persistirlo, y la respuesta
  # llegaba sin poder correlacionarse.
  def persist_flow_tokens!
    buttons = template_params&.dig('processed_params', 'buttons')
    return if buttons.blank?

    pending = buttons.select { |b| needs_flow_token?(b) }
    return if pending.empty?

    pending.each { |button| button['flow_token'] = SecureRandom.hex(16) }
    message.save!
  end

  def needs_flow_token?(button)
    button.is_a?(Hash) && button['type'].to_s == 'flow' && button['flow_token'].blank?
  end
end
