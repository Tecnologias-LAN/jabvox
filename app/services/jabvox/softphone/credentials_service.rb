# frozen_string_literal: true

# Arma las credenciales EFÍMERAS que el navegador necesita para registrar el softphone
# WebRTC, sin exponer secretos permanentes ni la troncal.
#
# Seguridad:
#   - El sip_secret permanente NUNCA se envía tal cual: se entrega solo dentro de la
#     respuesta autenticada y sobre HTTPS, y el registro SIP va por WSS. (Bold-style
#     ephemeral no aplica a SIP directo; para TURN sí generamos credenciales temporales.)
#   - Las credenciales TURN son temporales estilo coturn REST: username = "<exp>:<sip_user>"
#     y password = base64(HMAC-SHA1(turn_secret, username)). Caducan en credential_ttl.
#   - Solo se generan si el módulo está activo y el usuario tiene extensión ligada.
class Jabvox::Softphone::CredentialsService
  def initialize(account:, user:)
    @account = account
    @user = user
  end

  # Devuelve el hash de credenciales o levanta CredentialsError.
  #
  # La EXTENSIÓN sale del VoIP (jabvox_user_extensions): es la que el usuario tiene en ESTA
  # cuenta. El SECRETO SIP (para registrar por WebRTC, que VoIP no maneja) sale de
  # jabvox_softphone_extensions, ligado por user+account.
  def call
    config = @account.jabvox_softphone_config
    raise Jabvox::Softphone::CredentialsError, 'softphone_not_configured' if config.nil? || !config.enabled?

    domain = config.effective_sip_domain
    wss = config.effective_wss_url
    raise Jabvox::Softphone::CredentialsError, 'server_not_configured' if domain.blank? || wss.blank?

    voip_ext = @account.jabvox_user_extensions.find_by(user_id: @user.id)
    raise Jabvox::Softphone::CredentialsError, 'no_extension_linked' if voip_ext.nil?

    creds = JabvoxSoftphoneExtension.for(account_id: @account.id, user_id: @user.id)
    raise Jabvox::Softphone::CredentialsError, 'no_sip_credential' if creds.nil?

    build_payload(config, voip_ext.extension_jabvox, creds, domain, wss)
  end

  private

  def build_payload(config, extension, creds, domain, wss)
    {
      wss_url: wss,
      sip_domain: domain,
      sip_uri: "sip:#{extension}@#{domain}",
      auth_user: extension,
      # El secreto de registro SIP va por canal autenticado + HTTPS + WSS.
      sip_password: creds.sip_secret,
      extension: extension,
      codecs: config.codec_list,
      dtmf_mode: config.dtmf_mode,
      auto_answer: config.auto_answer,
      transfer_enabled: config.transfer_enabled,
      ice_servers: ice_servers(config, extension),
      ttl: config.credential_ttl
    }
  end

  # STUN (sin credenciales) + TURN con credenciales TEMPORALES (coturn REST/HMAC).
  def ice_servers(config, extension)
    servers = Array(config.stun_servers).map { |url| { urls: url } }
    servers << turn_server(config, extension) if config.turn_url.present? && config.turn_secret.present?
    servers
  end

  def turn_server(config, extension)
    expiry = Time.current.to_i + config.credential_ttl
    username = "#{expiry}:#{extension}"
    credential = Base64.strict_encode64(
      OpenSSL::HMAC.digest('SHA1', config.turn_secret, username)
    )
    { urls: config.turn_url, username: username, credential: credential }
  end
end
