# frozen_string_literal: true

# Heartbeat de presencia del softphone. El navegador reporta cada pocos segundos (y en
# cada cambio de estado) el estado en vivo de la extensión del usuario en ESTA cuenta:
# registrado / en llamada / caído / con error. El super admin lo lee para el panel de
# estado — SIN depender del AMI (restringido por IP y con falsos UNREACHABLE en WebRTC).
#
#   PATCH .../jabvox/softphone/presence  { state:, error:, remote_ip:, user_agent_info: }
#
# ROBUSTEZ: el guardado del heartbeat nunca hace fallar al softphone; si algo va mal,
# responde 200 igual (el estado en vivo es informativo, no crítico para la llamada).
class Api::V1::Accounts::Jabvox::Softphone::PresenceController < Api::V1::Accounts::Jabvox::BaseController
  jabvox_feature 'jabvox_softphone'

  VALID_STATES = %w[disconnected registering registered calling in_call failed].freeze

  def update
    ext = JabvoxSoftphoneExtension.for(account_id: Current.account.id, user_id: Current.user.id)
    return head(:no_content) if ext.nil? # sin credencial no hay presencia que reportar

    ext.update!(presence_attrs)
    head :no_content
  rescue StandardError => e
    Rails.logger.warn("[jabvox softphone] presence update failed: #{e.message}")
    head :ok
  end

  private

  def presence_attrs
    state = params[:state].to_s
    state = 'disconnected' unless VALID_STATES.include?(state)
    {
      live_state: state,
      last_seen_at: Time.current,
      last_error: params[:error].presence,
      remote_ip: request.remote_ip,
      user_agent_info: params[:user_agent_info].to_s.first(255).presence
    }
  end
end
