# frozen_string_literal: true

# Transporta un mensaje del Chat Aprovisionador de una cuenta al Hermes APROVISIONADOR
# global usando su API Server OpenAI-compatible (/v1/chat/completions). Ese Hermes ya sabe
# aprovisionar/crear el Hermes de la cuenta y ejecutar sus MCPs; Jabvox solo transporta el
# texto TAL CUAL (incluidos comandos como /model, /new — Hermes los interpreta) y devuelve
# la respuesta.
#
# Autenticación: token de SERVICIO del aprovisionador (cifrado). Nunca credenciales admin.
class Jabvox::Hermes::ProvisionerChatRelay
  Result = Struct.new(:success, :text, :error, keyword_init: true) do
    def success? = success
  end

  def initialize(account:, user:)
    @account = account
    @user = user
    @provisioner = JabvoxHermesProvisioner.instance
  end

  def send_message(content)
    return failure('El aprovisionador no está conectado.') unless @provisioner.connected?

    # Se envía el texto TAL CUAL a Hermes, SIN prompt de sistema. El aprovisionador ya trae
    # su propia identidad/instrucciones configuradas en su lado; Jabvox solo transporta.
    result = client.chat(nil, content.to_s)
    return failure(result.error) unless result.success?

    Result.new(success: true, text: result.text)
  rescue StandardError => e
    Rails.logger.error("[ProvisionerChatRelay] account=#{@account.id} #{e.class}")
    failure(e.message)
  end

  # Igual que send_message pero en STREAMING (SSE). Reenvía cada frame del stream del
  # aprovisionador al bloque `on_chunk` (texto + eventos hermes.tool.progress + [DONE]),
  # como el Chat IA de la cuenta. Devuelve el texto completo acumulado. El aprovisionamiento
  # puede tardar (crea teams/MCPs/servers); el streaming evita el timeout de la respuesta
  # sync y deja ver el progreso en vivo.
  # `history` son los mensajes previos de ESTA conversación ([{role:, content:}]). Sin ellos
  # el aprovisionador recibía solo el mensaje actual y cada turno era una conversación nueva:
  # no recordaba nada de lo hablado antes. `llm_overrides` permite elegir modelo/proveedor
  # desde el picker, como en el Chat IA.
  #
  # Va por el API de RUNS, que es el único modo en que el agente puede PEDIR APROBACIÓN antes
  # de ejecutar algo riesgoso. Con /chat/completions esa pregunta no existía y el agente se
  # quedaba bloqueado sin que el operador se enterara. Si el gateway no tiene /v1/runs (404),
  # se cae a /chat/completions para no romper instalaciones antiguas.
  def stream_message(content, on_chunk:, history: [], llm_overrides: nil, session_id: nil)
    unless @provisioner.connected?
      on_chunk.call("data: #{{ error: 'El aprovisionador no está conectado.' }.to_json}\n\n")
      return ''
    end

    run = runs_client.create(content, session_id: session_id, history: history, llm_overrides: llm_overrides)
    return stream_via_chat(content, history, llm_overrides, on_chunk) if fallback_to_chat?(run)

    stream_run(run, session_id, on_chunk)
  rescue StandardError => e
    Rails.logger.error("[ProvisionerChatRelay] stream account=#{@account.id} #{e.class}")
    on_chunk.call("data: #{{ error: e.message }.to_json}\n\n")
    ''
  end

  # Responde una aprobación pendiente de un run. `choice` sale de approval.choices.
  def approve(run_id, choice:, request_id: nil)
    runs_client.approve(run_id, choice: choice, request_id: request_id)
  end

  # Inyecta guía a un run en curso (/steer).
  def steer(run_id, text)
    runs_client.steer(run_id, text)
  end

  def stop(run_id)
    runs_client.stop(run_id)
  end

  # Fija el modelo de una sesión (/model).
  def set_session_model(session_id, model:, provider: nil)
    runs_client.set_session_model(session_id, model: model, provider: provider)
  end

  # Modelos que ofrece el aprovisionador (para el picker). Silencioso si falla: sin modelos
  # el chat sigue funcionando con el default.
  def model_options
    return [] unless @provisioner.connected?

    result = client.models
    result.success? ? result.data : []
  rescue StandardError => e
    Rails.logger.warn("[ProvisionerChatRelay] models #{e.class}: #{e.message}")
    []
  end

  private

  # Un 404 en /v1/runs significa gateway sin ese API (versión antigua): se sigue por el
  # camino viejo. Cualquier otro error SÍ se reporta, para no enmascarar fallos reales.
  def fallback_to_chat?(run)
    !run.success? && run.status == 404
  end

  # Anuncia el run al cliente (necesita el run_id para aprobar/steer/stop) y le retransmite
  # el stream de eventos del agente.
  def stream_run(run, session_id, on_chunk)
    return stream_error(run.error, on_chunk) unless run.success?

    run_id = run.data.is_a?(Hash) ? run.data['run_id'] : nil
    return stream_error('Hermes no devolvió run_id', on_chunk) if run_id.blank?

    on_chunk.call("event: run\ndata: #{{ run_id: run_id, session_id: session_id }.to_json}\n\n")
    runs_client.events(run_id, on_chunk: on_chunk)
    ''
  end

  def stream_via_chat(content, history, llm_overrides, on_chunk)
    Rails.logger.info('[ProvisionerChatRelay] /v1/runs no disponible, usando /chat/completions')
    messages = Array(history) + [{ role: 'user', content: content.to_s }]
    client.chat_stream(messages, on_chunk: on_chunk, llm_overrides: llm_overrides)
  end

  def stream_error(message, on_chunk)
    on_chunk.call("data: #{{ error: message }.to_json}\n\n")
    ''
  end

  def runs_client
    @runs_client ||= Jabvox::Hermes::RunsClient.new(
      base_url: @provisioner.base_url_jabvox,
      token: @provisioner.service_token_jabvox
    )
  end

  def client
    @client ||= Jabvox::Hermes::SessionsClient.new(
      base_url: @provisioner.base_url_jabvox,
      token: @provisioner.service_token_jabvox,
      model: ENV['HERMES_PROVISIONER_MODEL'].presence
    )
  end

  def failure(msg)
    Result.new(success: false, error: msg)
  end
end
