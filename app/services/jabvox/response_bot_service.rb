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

  def process # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    config = @account.jabvox_response_bot_configs.find_by(inbox_id: @conversation.inbox_id)
    return unless config&.enabled_jabvox?
    return unless config.jabvox_response_bot_seat

    # Stop responding once conversation is marked as paid
    return if @conversation.label_list.include?('proceso_pago')

    # Debounce: skip if a newer message exists (another job will handle it)
    latest_incoming = @conversation.messages
                                   .where(message_type: 'incoming', private: false)
                                   .order(created_at: :desc, id: :desc)
                                   .first
    return if latest_incoming && latest_incoming.id > @message.id

    model_record = config.jabvox_ai_chat_model ||
                   @account.jabvox_ai_chat_models.find_by(is_default_jabvox: true)
    return unless model_record

    audio_model = config.jabvox_audio_model || model_record
    image_model = config.jabvox_image_model || model_record
    seat = config.jabvox_response_bot_seat
    role = config.jabvox_response_bot_role
    active_labels = (config.active_labels_jabvox.presence || JabvoxResponseBotConfig::LABEL_CATEGORIES)

    pending = collect_pending_messages
    return if pending.empty?

    combined_text, image_urls = extract_content(pending, audio_model)
    return if combined_text.blank? && image_urls.empty?

    history = build_history(pending.map(&:id))
    context = build_documents_context
    result = call_ai(seat, role, model_record, image_model, active_labels, history, context, combined_text, image_urls,
                     config)
    return unless result

    apply_label(result[:label], active_labels)
    create_reply(result[:reply])
    send_payment_qr(config) if result[:send_payment_qr]
  rescue StandardError
    nil
  end

  private

  def collect_pending_messages
    last_bot = @conversation.messages
                            .where(message_type: 'outgoing', private: false)
                            .order(created_at: :desc)
                            .first

    scope = @conversation.messages
                         .includes(:attachments)
                         .where(message_type: 'incoming', private: false)
                         .order(created_at: :asc)

    scope = scope.where('created_at > ?', last_bot.created_at) if last_bot
    scope.to_a
  end

  def extract_content(messages, audio_model) # rubocop:disable Metrics/CyclomaticComplexity
    texts = []
    image_urls = []

    messages.each do |msg|
      texts << msg.content if msg.content.present?

      msg.attachments.each do |att|
        case att.file_type.to_s
        when 'audio'
          transcribed = transcribe_audio(att, audio_model)
          texts << "[Audio] #{transcribed}" if transcribed.present?
        when 'image'
          url = att.file_url
          image_urls << url if url.present?
        end
      end
    end

    [texts.join("\n"), image_urls]
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

  def build_history(exclude_ids)
    @conversation.messages
                 .where(private: false)
                 .where(message_type: %i[incoming outgoing])
                 .where.not(id: exclude_ids)
                 .reorder(created_at: :asc)
                 .last(MAX_HISTORY)
                 .filter_map do |m|
      next if m.content.blank?

      { role: m.message_type == 'incoming' ? 'user' : 'assistant', content: m.content.to_s }
    end
  end

  def build_documents_context
    bucket_config = @account.jabvox_ai_chat_config
    return '' if bucket_config&.bucket_url_jabvox.blank?

    bucket_service = Jabvox::AiChatBucketService.new(bucket_config)
    parts = []
    total_chars = 0

    %w[productos empresa].each do |category|
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

  def call_ai(seat, role, model_record, image_model, active_labels, history, context, combined_text, image_urls, config) # rubocop:disable Metrics/ParameterLists
    require 'openai'

    active_model = image_urls.any? ? image_model : model_record
    options = { access_token: active_model.api_key_jabvox.to_s }
    base = active_model.base_url_jabvox.presence
    options[:uri_base] = base if base
    client = OpenAI::Client.new(**options)

    messages = build_ai_messages(seat, role, active_labels, history, context, combined_text, image_urls, config)
    response = client.chat(
      parameters: {
        model: active_model.model_jabvox,
        messages: messages,
        temperature: 0.4,
        response_format: { type: 'json_object' }
      }
    )
    raw = response.dig('choices', 0, 'message', 'content') || ''
    parsed = JSON.parse(raw)
    {
      label: parsed['label'].to_s,
      reply: parsed['reply'].to_s,
      send_payment_qr: parsed['send_payment_qr'] == true
    }
  rescue StandardError
    nil
  end

  def build_ai_messages(seat, role, active_labels, history, context, combined_text, image_urls, config)
    system_content = build_system_prompt(seat, role, active_labels, context, config)
    msgs = [{ role: 'system', content: system_content }]
    history.each { |h| msgs << h }

    user_content = if image_urls.any?
                     parts = []
                     parts << { type: 'text', text: combined_text } if combined_text.present?
                     image_urls.each { |url| parts << { type: 'image_url', image_url: { url: url } } }
                     parts
                   else
                     combined_text
                   end

    msgs << { role: 'user', content: user_content }
    msgs
  end

  def build_system_prompt(seat, role, active_labels, context, config) # rubocop:disable Metrics/AbcSize
    label_rules = active_labels.map { |l| "- #{l}: #{LABEL_DESCRIPTIONS[l] || l}" }.join("\n")
    label_list = active_labels.join(', ')
    context_section = context.present? ? "\nDocumentos de referencia:\n#{context}\n" : ''
    role_section = role&.prompt_jabvox.present? ? "\n#{role.prompt_jabvox.to_s.strip}\n" : ''
    pricing_section = build_pricing_section(config)
    qr_available = @account.jabvox_response_bot_documents.enabled.for_category('qr_pago').exists?
    payment_instruction = qr_available ? payment_qr_instruction : ''

    <<~PROMPT
      #{seat.prompt_jabvox.to_s.strip}
      #{role_section}
      #{context_section}
      #{pricing_section}
      Eres un agente de ventas completo. Cuando el cliente realice un pedido, confirma los productos y pregunta si desea agregar algo más o si desea pagar.
      #{payment_instruction}
      IMPORTANTE: Debes responder SIEMPRE en formato JSON con exactamente estos campos:
      {"label": "categoria", "reply": "tu respuesta al cliente", "send_payment_qr": false}

      Etiquetas disponibles: #{label_list}
      Clasifica la conversación según la intención actual del cliente:
      #{label_rules}

      Usa solo etiquetas de la lista. Responde en el mismo idioma que el cliente.
    PROMPT
  end

  def payment_qr_instruction
    <<~INSTRUCTION
      Cuando el cliente indique explícitamente que desea pagar, responde confirmando y devuelve "send_payment_qr": true en el JSON.
      Usa la etiqueta "proceso_pago" cuando el cliente quiera pagar.
    INSTRUCTION
  end

  def build_pricing_section(config)
    parts = []
    parts << "Dirección de la empresa: #{config.company_address_jabvox}" if config.company_address_jabvox.present?
    parts << "Precio de entrega: #{config.price_per_km_jabvox} por km" if config.price_per_km_jabvox.present?
    parts.any? ? "\nInformación de entrega:\n#{parts.join("\n")}\n" : ''
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

  def send_payment_qr(config)
    qr_doc = @account.jabvox_response_bot_documents.enabled.for_category('qr_pago').first
    return unless qr_doc

    bucket_config = @account.jabvox_ai_chat_config
    return unless bucket_config&.bucket_url_jabvox.present?

    bucket_service = Jabvox::AiChatBucketService.new(bucket_config)
    qr_url = bucket_service.public_url(qr_doc.s3_key_jabvox)
    return unless qr_url.present?

    @conversation.messages.create!(
      account_id: @account.id,
      inbox_id: @conversation.inbox_id,
      message_type: :outgoing,
      content: qr_url
    )
  rescue StandardError
    nil
  end
end
