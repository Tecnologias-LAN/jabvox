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
      # Modo Hermes nativo: el Chat IA de la cuenta habla con SU Hermes por la Sessions API
      # (como Telegram). Reenvía el texto TAL CUAL (incluidos /model, /new...) y Hermes lo
      # interpreta. Jabvox no procesa comandos ni arma prompts para este modo.
      return chat_via_hermes(content) if hermes_native?

      messages = build_messages(content, mode, history)
      call_api(messages)
    end

    private

    # ¿El modelo seleccionado es el Hermes de la cuenta? (source='hermes' + handoff listo)
    def hermes_native?
      @model_record.respond_to?(:source_jabvox) && @model_record.source_jabvox == 'hermes' &&
        @account.jabvox_context_forge_handoff&.ready_for_chat?
    end

    # Comando para forzar sesión nueva (igual que /new en Telegram).
    HERMES_RESET_COMMAND = '/new'.freeze

    # Envía el turno al Hermes de la cuenta por la Sessions API nativa, con sesión persistente
    # por (cuenta, usuario). Reintenta con sesión nueva si Hermes ya no la reconoce (404/410).
    def chat_via_hermes(content)
      handoff = @account.jabvox_context_forge_handoff
      client = Jabvox::Hermes::SessionsClient.new(
        base_url: handoff.hermes_url, token: handoff.scoped_token
      )
      session = JabvoxHermesSession.for(account_id: @account.id, user_id: @user&.id, kind: 'account')
      session.reset! if content.to_s.strip == HERMES_RESET_COMMAND

      result = deliver_hermes(client, session, content)
      raise "Error al contactar Hermes: #{result.error}" unless result.success?

      session.remember!(result.session_id) if result.session_id.present?
      result.text
    end

    def deliver_hermes(client, session, content)
      sid = session.session_id_jabvox.presence || create_hermes_session!(client)
      result = client.chat(sid, content)
      return result unless !result.success? && [404, 410].include?(result.status)

      session.reset!
      client.chat(create_hermes_session!(client), content)
    end

    def create_hermes_session!(client)
      created = client.create_session
      raise created.error.to_s unless created.success?

      created.session_id
    end

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

      config = @account.jabvox_ai_chat_config
      bucket_service = Jabvox::AiChatBucketService.new(config&.documents_bucket_source)
      return '' unless bucket_service.configured?

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

    # Máximo de rondas de tool-calling por mensaje (evita bucles infinitos del modelo).
    MAX_TOOL_ROUNDS = 5

    def call_api(messages)
      client = build_client
      tools = tool_schemas_for_user
      # Sin tools permitidas → chat plano de siempre (retrocompatible).
      return plain_chat(client, messages) if tools.empty?

      chat_with_tools(client, messages, tools)
    rescue StandardError => e
      raise "Error al contactar el modelo de IA: #{e.message}"
    end

    def plain_chat(client, messages)
      response = client.chat(parameters: { model: @model_record.model_jabvox, messages: messages, temperature: 0.7 })
      response.dig('choices', 0, 'message', 'content') || ''
    end

    # Bucle de function-calling: se exponen SOLO las tools permitidas del usuario; cada
    # tool_call del modelo se ejecuta por el ToolExecutor (que REAUTORIZA en backend) y su
    # resultado vuelve al modelo hasta que produce una respuesta final.
    def chat_with_tools(client, messages, tools)
      convo = messages.dup
      MAX_TOOL_ROUNDS.times do
        response = client.chat(parameters: {
                                 model: @model_record.model_jabvox, messages: convo,
                                 temperature: 0.7, tools: tools, tool_choice: 'auto'
                               })
        message = response.dig('choices', 0, 'message') || {}
        calls = message['tool_calls']
        return message['content'].to_s if calls.blank?

        convo << message
        calls.each { |call| convo << run_tool_call(call) }
      end
      # Si agotó las rondas, una última respuesta sin tools.
      plain_chat(client, convo)
    end

    # Ejecuta una tool_call del modelo vía ToolExecutor y arma el mensaje 'tool' de respuesta.
    def run_tool_call(call)
      fn = call['function'] || {}
      name = fn['name']
      args = safe_json(fn['arguments'])
      result = Jabvox::Hermes::ToolExecutor.new(account: @account, user: @user).execute(name, args)
      payload = result.success? ? { ok: true, data: result.data } : { ok: false, error: result.error, status: result.status }
      { role: 'tool', tool_call_id: call['id'], name: name, content: payload.to_json }
    end

    def safe_json(str)
      JSON.parse(str.to_s)
    rescue JSON::ParserError
      {}
    end

    # Esquemas OpenAI-function de las tools que ESTE usuario puede usar (doble autorización
    # ya aplicada por el Authorizer). El modelo nunca ve tools que el usuario no puede ejecutar.
    def tool_schemas_for_user
      return [] unless @user

      Jabvox::Hermes::Authorizer.new(account: @account, user: @user).allowed_tools.map do |name|
        spec = Jabvox::Hermes::ToolRegistry.find(name)
        {
          type: 'function',
          function: {
            name: name, description: "#{spec[:permission]} - #{name}",
            parameters: json_schema_params(spec[:params] || {})
          }
        }
      end
    end

    def json_schema_params(params)
      props = params.transform_values { |type| { type: type == :integer ? 'integer' : 'string' } }
      { type: 'object', properties: props, required: params.keys.map(&:to_s) }
    end

    def build_client
      require 'openai'
      options = { access_token: hermes_scoped_api_key || @model_record.api_key_jabvox.to_s }
      base = @model_record.base_url_jabvox.presence
      options[:uri_base] = base if base
      OpenAI::Client.new(**options)
    end

    # AISLAMIENTO DURO: para un modelo servido por Hermes (source='hermes'), la api_key
    # SIEMPRE es el scoped token del handoff de ESTA cuenta — nunca el que traiga el
    # registro del modelo. Así un modelo Hermes de la cuenta N jamás puede ejecutarse con
    # el token de otra cuenta, aunque el registro estuviera mal copiado. Devuelve nil si
    # el modelo no es Hermes (usa su api_key normal).
    def hermes_scoped_api_key
      return nil unless @model_record.respond_to?(:source_jabvox) && @model_record.source_jabvox == 'hermes'

      handoff = @account.jabvox_context_forge_handoff
      return nil unless handoff&.ready_for_chat?

      handoff.scoped_token
    end
  end
end
