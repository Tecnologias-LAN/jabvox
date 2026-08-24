# frozen_string_literal: true

# Transporta un mensaje del Chat Aprovisionador de una cuenta al Hermes APROVISIONADOR
# global (endpoint OpenAI-compatible). Ese Hermes ya sabe aprovisionar/crear el Hermes de la
# cuenta y ejecutar sus MCPs de infraestructura; Jabvox solo transporta el mensaje con la
# identidad de la cuenta y el usuario, y devuelve el texto de respuesta.
#
# Autenticación: token de SERVICIO del aprovisionador (cifrado). Nunca credenciales admin.
# Contexto: se envía account_id/user_id como metadatos del mensaje de sistema para que el
# aprovisionador sepa para qué cuenta actuar (el aislamiento real lo impone el propio
# aprovisionador por su token, no el prompt).
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

    text = call_provisioner(content)
    Result.new(success: true, text: text)
  rescue StandardError => e
    Rails.logger.error("[ProvisionerChatRelay] account=#{@account.id} #{e.class}")
    failure(e.message)
  end

  private

  def call_provisioner(content)
    require 'openai'
    client = OpenAI::Client.new(
      access_token: @provisioner.service_token_jabvox,
      uri_base: @provisioner.base_url_jabvox
    )
    # Hermes ignora el nombre del modelo (usa el suyo configurado); enviamos uno neutro.
    # Configurable por si tu Hermes exige un id concreto (ver GET /v1/models).
    response = client.chat(parameters: {
                             model: ENV['HERMES_PROVISIONER_MODEL'].presence || 'hermes',
                             messages: [
                               { role: 'system', content: context_message },
                               { role: 'user', content: content }
                             ],
                             temperature: 0.5
                           })
    response.dig('choices', 0, 'message', 'content').to_s
  end

  # Contexto para el aprovisionador: PARA QUÉ cuenta/usuario actúa. El aislamiento efectivo
  # lo aplica el aprovisionador con su propia autorización, no este texto.
  def context_message
    "Actúas como Hermes Aprovisionador para la cuenta Jabvox #{@account.id} " \
      "(usuario #{@user&.id}). Ayuda a aprovisionar/gestionar el Hermes de esa cuenta y sus MCPs. " \
      'Trabaja solo sobre esa cuenta.'
  end

  def failure(msg)
    Result.new(success: false, error: msg)
  end
end
