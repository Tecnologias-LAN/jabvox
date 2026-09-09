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
  def stream_message(content, on_chunk:)
    unless @provisioner.connected?
      on_chunk.call("data: #{{ error: 'El aprovisionador no está conectado.' }.to_json}\n\n")
      return ''
    end

    client.chat_stream([{ role: 'user', content: content.to_s }], on_chunk: on_chunk)
  rescue StandardError => e
    Rails.logger.error("[ProvisionerChatRelay] stream account=#{@account.id} #{e.class}")
    on_chunk.call("data: #{{ error: e.message }.to_json}\n\n")
    ''
  end

  private

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
