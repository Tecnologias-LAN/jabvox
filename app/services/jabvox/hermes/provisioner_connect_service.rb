# frozen_string_literal: true

# Conecta (desde super admin) el Hermes APROVISIONADOR global ÚNICO: guarda su URL (host:
# puerto ZeroTier), token de servicio (cifrado), usuario de servicio (segundo factor) y
# secreto de callback (cifrado), y verifica que responde por la Sessions API nativa de Hermes.
#
# Doble seguridad: el aprovisionador tiene acceso amplio (todas las cuentas, contraseñas
# incluidas) MENOS borrar, así que su callback exige token + usuario de servicio + secreto.
class Jabvox::Hermes::ProvisionerConnectService
  Result = Struct.new(:success, :provisioner, :error, keyword_init: true) do
    def success? = success
  end

  def initialize(base_url:, service_token:, service_user: nil, callback_secret: nil, sessions_path: nil)
    @base_url = base_url.to_s.strip
    @service_token = service_token.to_s.strip
    @service_user = service_user
    @callback_secret = callback_secret.to_s.strip
    @sessions_path = sessions_path.to_s.strip
  end

  def call
    return failure('La URL del aprovisionador es requerida.') if @base_url.blank?
    return failure('URL inválida.') unless valid_url?(@base_url)
    return failure('El token de servicio es requerido.') if @service_token.blank?

    ping = verify
    return failure(ping.error) unless ping.success?

    provisioner = persist!
    Result.new(success: true, provisioner: provisioner)
  rescue StandardError => e
    JabvoxHermesProvisioner.instance.mark_error!(e.message)
    failure(e.message)
  end

  private

  def valid_url?(url)
    uri = URI.parse(url)
    uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end

  # Verifica con la Sessions API nativa de Hermes (health), respetando sessions_path.
  def verify
    client = Jabvox::Hermes::SessionsClient.new(
      base_url: @base_url, token: @service_token, sessions_path: effective_sessions_path
    )
    res = client.health
    res.success? ? ok : failure(res.error || 'El aprovisionador no respondió health')
  end

  def persist!
    provisioner = JabvoxHermesProvisioner.instance
    provisioner.sessions_path_jabvox = effective_sessions_path
    provisioner.mark_connected!(
      base_url: @base_url, service_token: @service_token,
      service_user: @service_user, callback_secret: @callback_secret.presence
    )
    provisioner
  end

  def effective_sessions_path
    @sessions_path.presence || '/api/sessions'
  end

  def ok
    Result.new(success: true)
  end

  def failure(msg)
    Result.new(success: false, error: msg)
  end
end
