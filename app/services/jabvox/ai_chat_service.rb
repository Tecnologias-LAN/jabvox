module Jabvox
  class AiChatService
    MAX_HISTORY = 20
    MAX_CONTEXT_CHARS = 15_000

    def initialize(account:, user:, model_record:)
      @account = account
      @user = user
      @model_record = model_record
    end

    def send_message(content:, session_id:, mode:, history: [])
      messages = build_messages(content, mode, history)
      response_text = call_api(messages)
      response_text
    end

    private

    def build_messages(content, mode, history)
      system_msg = build_system_message(mode)
      msgs = [{ role: 'system', content: system_msg }]

      history.each do |m|
        msgs << { role: m.role_jabvox, content: m.content_jabvox }
      end

      msgs << { role: 'user', content: content }
      msgs
    end

    def build_system_message(mode)
      if mode == 'documents'
        context = fetch_documents_context
        "Eres un asistente útil. Responde únicamente basándote en los siguientes documentos:\n\n#{context}"
      else
        'Eres un asistente útil y amigable. Responde de forma clara y concisa.'
      end
    end

    def fetch_documents_context
      enabled_docs = @account.jabvox_ai_chat_documents.enabled
      return '' if enabled_docs.empty?

      bucket_config = @account.jabvox_ai_chat_config
      return '' unless bucket_config&.bucket_url_jabvox.present?

      bucket_service = Jabvox::AiChatBucketService.new(bucket_config)
      parts = []
      total_chars = 0

      enabled_docs.each do |doc|
        break if total_chars >= MAX_CONTEXT_CHARS

        content = bucket_service.read_document(doc.s3_key_jabvox)
        next unless content

        truncated = content[0, MAX_CONTEXT_CHARS - total_chars]
        parts << "## #{doc.name_jabvox}\n#{truncated}"
        total_chars += truncated.length
      rescue StandardError
        next
      end

      parts.join("\n\n---\n\n")
    end

    def call_api(messages)
      client = build_client
      response = client.chat(
        parameters: {
          model: @model_record.model_jabvox,
          messages: messages,
          temperature: 0.7
        }
      )
      response.dig('choices', 0, 'message', 'content') || ''
    rescue StandardError => e
      raise "Error al contactar el modelo de IA: #{e.message}"
    end

    def build_client
      require 'openai'
      options = { access_token: @model_record.api_key_jabvox.to_s }
      base = @model_record.base_url_jabvox.presence
      options[:uri_base] = base if base
      OpenAI::Client.new(**options)
    end
  end
end
