# frozen_string_literal: true

# Conecta (desde super admin) el Hermes APROVISIONADOR global ÚNICO como UN AGENTE: guarda
# su nombre visible, el nombre del agente en Hermes, su URL (host:puerto/p/<agente>/v1) y su
# token (cifrado), y verifica que responde por la Sessions API nativa de Hermes.
#
# Es un agente normal: no fabrica Hermes por cuenta ni tiene 2º factor. Las cuentas ligadas
# usan este mismo agente en el Chat Aprovisionador.
class Jabvox::Hermes::ProvisionerConnectService
  Result = Struct.new(:success, :provisioner, :error, keyword_init: true) do
    def success? = success
  end

  def initialize(base_url:, service_token:, name: nil, hermes_agent_name: nil)
    @base_url = base_url.to_s.strip
    @service_token = service_token.to_s.strip
    @name = name.to_s.strip
    @hermes_agent_name = hermes_agent_name.to_s.strip
  end

  def call
    return failure('La URL del agente es requerida.') if @base_url.blank?
    return failure('URL inválida.') unless valid_url?(@base_url)
    return failure('El token del agente es requerido.') if @service_token.blank?

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

  # Verifica con la Sessions API nativa de Hermes (health).
  def verify
    client = Jabvox::Hermes::SessionsClient.new(base_url: @base_url, token: @service_token)
    res = client.health
    res.success? ? ok : failure(res.error || 'El agente no respondió health')
  end

  def persist!
    provisioner = JabvoxHermesProvisioner.instance
    provisioner.mark_connected!(
      base_url: @base_url, service_token: @service_token,
      name: @name.presence, hermes_agent_name: @hermes_agent_name.presence
    )
    provisioner
  end

  def ok
    Result.new(success: true)
  end

  def failure(msg)
    Result.new(success: false, error: msg)
  end
end
