# frozen_string_literal: true

# Estado en vivo del softphone de una cuenta, para el panel de Super Admin. Reporta:
#   - el estado GENERAL de la cuenta (deshabilitado / sin config / servidor incompleto / ok)
#   - por cada extensión ligada: su estado EN VIVO reportado por el propio navegador
#     (registrado / en llamada / caído / con error), con último visto e IP.
#
# FUENTE DE VERDAD: la presencia que cada softphone reporta al backend (heartbeat), NO el
# AMI. El AMI de Issabel está restringido por IP (no accesible desde dev) y da falsos
# UNREACHABLE en clientes WebRTC (el qualify OPTIONS no vuelve por WSS). El heartbeat
# funciona en dev y producción, para chan_sip y PJSIP por igual.
# rubocop:disable Style/ClassAndModuleChildren
module Jabvox
  module Softphone
    class StatusService
      # Estados generales de la cuenta.
      DISABLED = 'disabled'                 # módulo no activo en la cuenta
      NO_CONFIG = 'no_config'               # falta la configuración WebRTC
      NOT_CONFIGURED = 'server_missing'     # config sin WSS/dominio
      OK = 'ok'

      # Ventana tras la cual un heartbeat se considera obsoleto (extensión "caída").
      STALE_AFTER = 60 # segundos

      # Mapa del estado reportado por el navegador al estado mostrable en el panel.
      LIVE_STATE_MAP = {
        'registered' => 'online',
        'calling' => 'on_call',
        'in_call' => 'on_call',
        'failed' => 'error',
        'registering' => 'connecting'
      }.freeze

      def initialize(account)
        @account = account
      end

      # { account_status:, server:, reason:, error_code:,
      #   extensions: [ { extension, user, has_credential, webrtc_enabled,
      #                    state, live_state, last_seen_at, last_error, remote_ip } ] }
      def call
        return base(DISABLED) unless @account.feature_enabled?('jabvox_softphone')

        config = @account.jabvox_softphone_config
        return base(NO_CONFIG) if config.nil?
        return base(NOT_CONFIGURED, server: config.effective_wss_url) unless config.operational?

        base(OK, server: config.effective_wss_url, extensions: extensions_with_state)
      end

      private

      def base(status, server: nil, reason: nil, error_code: nil, extensions: [])
        {
          account_status: status, server: server, reason: reason,
          error_code: error_code, extensions: extensions
        }
      end

      # Extensiones de VoIP de la cuenta, con su usuario, credencial y estado EN VIVO
      # (presencia reportada por el navegador de ese usuario).
      def extensions_with_state
        creds = JabvoxSoftphoneExtension.where(account_id: @account.id).index_by(&:user_id)
        @account.jabvox_user_extensions.includes(:user).order(:extension_jabvox).map do |ve|
          cred = creds[ve.user_id]
          {
            extension: ve.extension_jabvox,
            user: ve.user&.name || ve.user&.email,
            has_credential: cred.present?,
            webrtc_enabled: cred&.webrtc_enabled || false,
            state: live_state_for(cred),
            live_state: cred&.live_state,
            last_seen_at: cred&.last_seen_at,
            last_error: cred&.last_error,
            remote_ip: cred&.remote_ip,
            user_agent_info: cred&.user_agent_info
          }
        end
      end

      # Traduce el heartbeat a un estado mostrable. Si el último visto es viejo, la
      # extensión se considera caída aunque su último estado reportado fuera "registered".
      def live_state_for(cred)
        return 'no_credential' if cred.nil?
        return 'never_connected' if cred.last_seen_at.nil?
        return 'offline' if cred.last_seen_at < STALE_AFTER.seconds.ago

        LIVE_STATE_MAP.fetch(cred.live_state, 'offline')
      end
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
