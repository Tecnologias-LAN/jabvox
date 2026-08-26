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

    client = Jabvox::Hermes::SessionsClient.new(
      base_url: @provisioner.base_url_jabvox,
      token: @provisioner.service_token_jabvox,
      model: ENV['HERMES_PROVISIONER_MODEL'].presence
    )
    # Se envía el texto TAL CUAL a Hermes, SIN prompt de sistema. El aprovisionador ya trae
    # su propia identidad/instrucciones configuradas en su lado; Jabvox solo transporta.
    result = client.chat(nil, content.to_s)
    return failure(result.error) unless result.success?

    Result.new(success: true, text: result.text)
  rescue StandardError => e
    Rails.logger.error("[ProvisionerChatRelay] account=#{@account.id} #{e.class}")
    failure(e.message)
  end

  private

  def failure(msg)
    Result.new(success: false, error: msg)
  end
end
