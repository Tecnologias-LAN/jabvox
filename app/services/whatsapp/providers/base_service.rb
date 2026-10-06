#######################################
# To create a whatsapp provider
# - Inherit this as the base class.
# - Implement `send_message` method in your child class.
# - Implement `send_template_message` method in your child class.
# - Implement `sync_templates` method in your child class.
# - Implement `validate_provider_config` method in your child class.
# - Use Childclass.new(whatsapp_channel: channel).perform.
######################################

class Whatsapp::Providers::BaseService
  pattr_initialize [:whatsapp_channel!]

  def send_message(_phone_number, _message)
    raise 'Overwrite this method in child class'
  end

  def send_template(_phone_number, _template_info, _message)
    raise 'Overwrite this method in child class'
  end

  def sync_template
    raise 'Overwrite this method in child class'
  end

  def validate_provider_config
    raise 'Overwrite this method in child class'
  end

  def error_message
    raise 'Overwrite this method in child class'
  end

  def process_response(response, message)
    parsed_response = response.parsed_response
    if response.success? && parsed_response['error'].blank?
      parsed_response['messages'].first['id']
    else
      handle_error(response, message)
      nil
    end
  end

  def handle_error(response, message)
    Rails.logger.error response.body
    return if message.blank?

    # Antes: `return if error_message.blank?`. Cuando el proveedor respondía un fallo sin
    # texto legible (timeout, 502, HTML de error, cuerpo vacío), el mensaje se quedaba en
    # "sent" para siempre: en la conversación salía el relojito y nadie sabía que no había
    # salido. Un envío fallido SIEMPRE se marca como fallido, haya o no texto de Meta.
    message.external_error = describe_error(response)
    message.status = :failed
    message.save!
  end

  # Texto que ve el agente en la conversación. Lleva el código de Meta cuando existe,
  # porque es lo que distingue un problema de la cuenta de WhatsApp (plantilla no
  # aprobada, número no verificado, límite de calidad) de un fallo de envío de la app.
  def describe_error(response)
    detail = error_message(response).presence
    code = error_code(response)
    http = response.respond_to?(:code) ? response.code : nil

    return "#{detail} (WhatsApp #{code})" if detail && code
    return detail if detail
    return "WhatsApp rechazó el envío (error #{code})" if code

    "El proveedor no aceptó el envío (HTTP #{http || 'sin respuesta'})"
  end

  # Código numérico de Meta / 360dialog. Sobrescribible por proveedor.
  def error_code(response)
    parsed = response.respond_to?(:parsed_response) ? response.parsed_response : nil
    return nil unless parsed.is_a?(Hash)

    parsed.dig('error', 'code') || parsed.dig('meta', 'http_code')
  end

  # WhatsApp coexistence / username migration: a contact may become addressable only by a Business-Scoped
  # User ID (BSUID, e.g. "BR.123..."), with no phone number available. The Cloud API requires a BSUID to be
  # passed in the `recipient` field (with recipient_type: individual), NOT in `to`. Passing a BSUID in `to`
  # returns HTTP 200 with a message id but the message is silently dropped: the "CC." prefix is stripped and
  # the remainder is treated as a phone number (wa_id), which never resolves. Phone numbers keep using `to`.
  # See: https://developers.facebook.com/documentation/business-messaging/whatsapp/business-scoped-user-ids/
  def recipient_params(identifier)
    if identifier.to_s.match?(RegexHelper::WHATSAPP_BSUID_REGEX)
      { recipient_type: 'individual', recipient: identifier }
    else
      { to: identifier }
    end
  end

  def create_buttons(items)
    buttons = []
    items.each do |item|
      button = { :type => 'reply', 'reply' => { 'id' => item['value'], 'title' => item['title'] } }
      buttons << button
    end
    buttons
  end

  def create_rows(items)
    rows = []
    items.each do |item|
      row = { 'id' => item['value'], 'title' => item['title'] }
      rows << row
    end
    rows
  end

  def create_payload(type, message_content, action)
    {
      'type': type,
      'body': {
        'text': message_content
      },
      'action': action
    }
  end

  def create_payload_based_on_items(message)
    if message.content_attributes['items'].length <= 3
      create_button_payload(message)
    else
      create_list_payload(message)
    end
  end

  def create_button_payload(message)
    buttons = create_buttons(message.content_attributes['items'])
    json_hash = { 'buttons' => buttons }
    create_payload('button', message.outgoing_content, JSON.generate(json_hash))
  end

  def create_list_payload(message)
    rows = create_rows(message.content_attributes['items'])
    section1 = { 'rows' => rows }
    sections = [section1]
    json_hash = { :button => I18n.t('conversations.messages.whatsapp.list_button_label'), 'sections' => sections }
    create_payload('list', message.outgoing_content, JSON.generate(json_hash))
  end
end
