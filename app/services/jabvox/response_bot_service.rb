class Jabvox::ResponseBotService
  MAX_HISTORY = 10
  MAX_CONTEXT_CHARS = 10_000

  LABEL_DESCRIPTIONS = {
    'proceso_venta' => 'el cliente pregunta, cotiza, se interesa o hace un pedido',
    'proceso_pago' => 'el cliente va a pagar, envió el pago o ya hizo un pedido y quiere confirmarlo',
    'quejas_y_reclamos' => 'el cliente está molesto, hace una queja o un reclamo',
    'soporte' => 'el cliente necesita ayuda técnica o de soporte con algún tema'
  }.freeze

  def initialize(message)
    @message = message
    @conversation = message.conversation
    @account = message.account
  end

  def process # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/AbcSize
    config = @account.jabvox_response_bot_configs.find_by(inbox_id: @conversation.inbox_id)
    return unless config&.enabled_jabvox?
    return unless config.jabvox_response_bot_seat

    model_record = config.jabvox_ai_chat_model ||
                   @account.jabvox_ai_chat_models.find_by(is_default_jabvox: true)
    return unless model_record

    audio_model = config.jabvox_audio_model || model_record
    seat = config.jabvox_response_bot_seat
    role = config.jabvox_response_bot_role
    active_labels = (config.active_labels_jabvox.presence || JabvoxResponseBotConfig::LABEL_CATEGORIES)

    message_text = transcribe_audio_if_needed(audio_model) || @message.content
    return if message_text.blank?

    history = build_history
    context = build_documents_context(active_labels)
    result = call_ai(seat, role, model_record, active_labels, history, context, message_text)
    return unless result

    apply_label(result[:label], active_labels)
    create_reply(result[:reply])
  rescue StandardError
    nil
  end

  private

  def transcribe_audio_if_needed(model_record)
    return nil if @message.content.present?

    audio_attachment = @message.attachments.find do |a|
      a.file_type.to_s == 'audio' || a.content_type.to_s.start_with?('audio/')
    end
    return nil unless audio_attachment

    transcribe_audio(audio_attachment, model_record)
  rescue StandardError
    nil
  end

  def transcribe_audio(attachment, model_record)
    require 'openai'
    require 'open-uri'

    options = { access_token: model_record.api_key_jabvox.to_s }
    base = model_record.base_url_jabvox.presence
    options[:uri_base] = base if base
    client = OpenAI::Client.new(**options)

    file_url = attachment.file_url
    extension = File.extname(attachment.file.blob.filename.to_s).presence || '.ogg'
    Tempfile.create(['audio', extension], binmode: true) do |tmp|
      tmp.write(URI.open(file_url, &:read)) # rubocop:disable Security/Open
      tmp.rewind
      response = client.audio.transcribe(
        parameters: { model: 'whisper-1', file: tmp }
      )
      response['text'].presence
    end
  rescue StandardError
    nil
  end

  def build_history
    @conversation.messages
                 .where(private: false)
                 .where(message_type: %i[incoming outgoing])
                 .reorder(created_at: :asc)
                 .last(MAX_HISTORY)
                 .filter_map do |m|
      next if m.content.blank?

      { role: m.message_type == 'incoming' ? 'user' : 'assistant', content: m.content.to_s }
    end
  end

  def build_documents_context(active_labels) # rubocop:disable Metrics/CyclomaticComplexity
    bucket_config = @account.jabvox_ai_chat_config
    return '' if bucket_config&.bucket_url_jabvox.blank?

    bucket_service = Jabvox::AiChatBucketService.new(bucket_config)
    parts = []
    total_chars = 0

    active_labels.each do |category|
      @account.jabvox_response_bot_documents.enabled.for_category(category).ordered.each do |doc|
        break if total_chars >= MAX_CONTEXT_CHARS

        content = bucket_service.read_document(doc.s3_key_jabvox)
        next unless content

        truncated = content[0, MAX_CONTEXT_CHARS - total_chars]
        parts << "### [#{category}] #{doc.name_jabvox}\n#{truncated}"
        total_chars += truncated.length
      rescue StandardError
        next
      end
    end

    parts.join("\n\n---\n\n")
  end

  def call_ai(seat, role, model_record, active_labels, history, context, message_text) # rubocop:disable Metrics/ParameterLists
    require 'openai'
    options = { access_token: model_record.api_key_jabvox.to_s }
    base = model_record.base_url_jabvox.presence
    options[:uri_base] = base if base
    client = OpenAI::Client.new(**options)

    messages = build_ai_messages(seat, role, active_labels, history, context, message_text)
    response = client.chat(
      parameters: {
        model: model_record.model_jabvox,
        messages: messages,
        temperature: 0.4,
        response_format: { type: 'json_object' }
      }
    )
    raw = response.dig('choices', 0, 'message', 'content') || ''
    parsed = JSON.parse(raw)
    { label: parsed['label'].to_s, reply: parsed['reply'].to_s }
  rescue StandardError
    nil
  end

  def build_ai_messages(seat, role, active_labels, history, context, message_text)
    system_content = build_system_prompt(seat, role, active_labels, context)
    msgs = [{ role: 'system', content: system_content }]
    history.each { |h| msgs << h }
    msgs << { role: 'user', content: message_text }
    msgs
  end

  def build_system_prompt(seat, role, active_labels, context)
    label_rules = active_labels.map { |l| "- #{l}: #{LABEL_DESCRIPTIONS[l] || l}" }.join("\n")
    label_list = active_labels.join(', ')
    context_section = context.present? ? "\nDocumentos de referencia:\n#{context}\n" : ''
    role_section = role&.prompt_jabvox.present? ? "\n#{role.prompt_jabvox.to_s.strip}\n" : ''

    <<~PROMPT
      #{seat.prompt_jabvox.to_s.strip}
      #{role_section}
      #{context_section}
      IMPORTANTE: Debes responder SIEMPRE en formato JSON con exactamente dos campos:
      {"label": "categoria", "reply": "tu respuesta al cliente"}

      Etiquetas disponibles: #{label_list}
      Clasifica la conversación según la intención actual del cliente:
      #{label_rules}

      Usa solo etiquetas de la lista. Responde en el mismo idioma que el cliente.
    PROMPT
  end

  def apply_label(label, active_labels)
    return unless label.present? && active_labels.include?(label)

    current_labels = @conversation.label_list.to_a
    non_bot_labels = current_labels.reject { |l| JabvoxResponseBotConfig::LABEL_CATEGORIES.include?(l) }
    @conversation.update_labels(non_bot_labels + [label])
  rescue StandardError
    nil
  end

  def create_reply(reply)
    return if reply.blank?

    @conversation.messages.create!(
      account_id: @account.id,
      inbox_id: @conversation.inbox_id,
      message_type: :outgoing,
      content: reply
    )
  rescue StandardError
    nil
  end
end
