# frozen_string_literal: true

# Transporta un mensaje del Chat Aprovisionador de una cuenta al Hermes APROVISIONADOR
# global usando la Sessions REST API NATIVA de Hermes (no OpenAI). Ese Hermes ya sabe
# aprovisionar/crear el Hermes de la cuenta y ejecutar sus MCPs; Jabvox solo transporta el
# texto TAL CUAL (incluidos comandos como /model, /new — Hermes los interpreta) y devuelve
# la respuesta.
#
# Sesión persistente por (cuenta, usuario, 'provisioner'): se reutiliza el session_id para
# conversación continua, igual que Telegram mapea chat_id → sesión.
# Autenticación: token de SERVICIO del aprovisionador (cifrado). Nunca credenciales admin.
class Jabvox::Hermes::ProvisionerChatRelay
  Result = Struct.new(:success, :text, :error, keyword_init: true) do
    def success? = success
  end

  # Comando para forzar sesión nueva (como /new en Telegram).
  RESET_COMMAND = '/new'

  def initialize(account:, user:)
    @account = account
    @user = user
    @provisioner = JabvoxHermesProvisioner.instance
  end

  def send_message(content)
    return failure('El aprovisionador no está conectado.') unless @provisioner.connected?

    client = build_client
    session = session_record
    session.reset! if content.to_s.strip == RESET_COMMAND

    result = deliver(client, session, content)
    return failure(result.error) unless result.success?

    session.remember!(result.session_id) if result.session_id.present?
    Result.new(success: true, text: result.text)
  rescue StandardError => e
    Rails.logger.error("[ProvisionerChatRelay] account=#{@account.id} #{e.class}")
    failure(e.message)
  end

  private

  def build_client
    Jabvox::Hermes::SessionsClient.new(
      base_url: @provisioner.base_url_jabvox,
      token: @provisioner.service_token_jabvox,
      sessions_path: @provisioner.sessions_path
    )
  end

  def session_record
    JabvoxHermesSession.for(account_id: @account.id, user_id: @user&.id, kind: 'provisioner')
  end

  # Asegura una sesión viva y envía el turno. Si Hermes ya no reconoce la sesión (404/410),
  # crea una nueva y reintenta una vez.
  def deliver(client, session, content)
    sid = session.session_id_jabvox.presence || create_session!(client)
    result = client.chat(sid, content)
    return result unless session_expired?(result)

    session.reset!
    client.chat(create_session!(client), content)
  end

  def create_session!(client)
    created = client.create_session
    raise created.error.to_s unless created.success?

    created.session_id
  end

  def session_expired?(result)
    !result.success? && [404, 410].include?(result.status)
  end

  def failure(msg)
    Result.new(success: false, error: msg)
  end
end
