module Whatsapp::IncomingMessageServiceHelpers
  def download_attachment_file(attachment_payload)
    Down.download(inbox.channel.media_url(attachment_payload[:id]), headers: inbox.channel.api_headers)
  end

  def conversation_params
    {
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      contact_id: @contact.id,
      contact_inbox_id: @contact_inbox.id
    }
  end

  def processed_params
    @processed_params ||= params
  end

  def account
    @account ||= inbox.account
  end

  def message_type
    messages_data.first[:type]
  end

  def message_content(message)
    message.dig(:text, :body) ||
      message.dig(:button, :text) ||
      message.dig(:interactive, :button_reply, :title) ||
      message.dig(:interactive, :list_reply, :title) ||
      flow_response_content(message) ||
      message.dig(:name, :formatted_name)
  end

  # A completed WhatsApp Flow arrives as interactive.type == 'nfm_reply', with the
  # submitted answers JSON-encoded (as a STRING, not an object) inside
  # nfm_reply.response_json. Without this, the message content is nil ("No hay
  # contenido disponible" in the UI) and the answers are silently lost — confirmed
  # against a real production send and matching a known Chatwoot gap (issue #13970).
  # Renders a readable "campo: valor" summary; the raw parsed answers also go into
  # content_attributes (see message_content_attributes) for automations/API consumers.
  def flow_response_content(message)
    answers = flow_response_answers(message)
    return nil if answers.blank?

    answers.except('flow_token').map { |key, value| "#{humanize_flow_field(key)}: #{humanize_flow_value(value)}" }.join("\n")
  end

  # Meta's answers hash always carries the flow_token alongside the actual
  # screen answers (see flow_response_answers) — it's routing metadata, not
  # something to show the agent as if the user had typed it.
  def humanize_flow_value(value)
    Array(value).join(', ')
  end

  # Meta's raw nfm_reply.response_json, parsed — includes BOTH the user's
  # answers (screen_N_Label_M keys) and the flow_token that was minted when
  # Jabvox sent the template (see PopulateTemplateParametersService), which is
  # what lets a bulk-send report match this exact reply to that exact send,
  # rather than guessing from "next incoming message after the send".
  def flow_response_answers(message)
    raw = message.dig(:interactive, :nfm_reply, :response_json)
    return nil if raw.blank?

    JSON.parse(raw)
  rescue JSON::ParserError
    Rails.logger.warn("[WHATSAPP] Could not parse Flow response_json: #{raw.to_s.truncate(200)}")
    nil
  end

  # Structured Flow answers ({"flow_token" => "...", "screen_0_Rating_0" => "Excelente", ...}),
  # for automations/API consumers and for matching a bulk-send recipient to its
  # reply — the readable summary already lives in `content`.
  def add_flow_response_attributes(content_attrs, message)
    flow_answers = flow_response_answers(message)
    content_attrs[:whatsapp_flow_response] = flow_answers if flow_answers.present?
    content_attrs
  end

  # Meta's field keys look like "screen_0_Rating_0" (screen index + field label +
  # field index) — strip the screen/index scaffolding so agents see "Rating"
  # instead of the raw internal key.
  def humanize_flow_field(key)
    key.to_s.sub(/\Ascreen_\d+_/, '').sub(/_\d+\z/, '').tr('_', ' ')
  end

  def file_content_type(file_type)
    return :image if %w[image sticker].include?(file_type)
    return :audio if %w[audio voice].include?(file_type)
    return :video if ['video'].include?(file_type)
    return :location if ['location'].include?(file_type)
    return :contact if ['contacts'].include?(file_type)

    :file
  end

  def unprocessable_message_type?(message_type)
    %w[reaction ephemeral request_welcome].include?(message_type)
  end

  def processed_waid(waid)
    Whatsapp::PhoneNumberNormalizationService.new(inbox).normalize_and_find_contact_by_provider(waid, :cloud)
  end

  def whatsapp_phone_number(identifier)
    identifier = identifier.to_s
    return if identifier.blank?
    return unless identifier.match?(/\A\d{1,15}\z/)

    identifier
  end

  def error_webhook_event?(message)
    message.key?('errors')
  end

  def log_error(message)
    Rails.logger.warn "Whatsapp Error: #{message['errors'][0]['title']} - contact: #{message['from']}"
  end

  def process_in_reply_to(message)
    @in_reply_to_external_id = message['context']&.[]('id')
  end

  def referral_attributes(message)
    return {} if outgoing_echo

    message[:referral]&.to_h&.deep_stringify_keys || {}
  end

  def find_message_by_source_id(source_id)
    return unless source_id

    @message = Message.find_by(source_id: source_id)
  end

  def lock_message_source_id!
    return false if messages_data.blank?

    Whatsapp::MessageDedupLock.new(messages_data.first[:id]).acquire!
  end
end
