# frozen_string_literal: true

# Panel Super Admin: CRUD de la configuración WebRTC del softphone por cuenta, con un
# formulario tipo wizard (paso a paso). Los codecs llegan como array de checkboxes; los
# stun_servers como texto (uno por línea) que se convierte a array.
class SuperAdmin::JabvoxSoftphoneConfigsController < SuperAdmin::ApplicationController
  def resource_params
    permitted = params.require(:jabvox_softphone_config).permit(
      :account_id, :enabled, :wss_url, :sip_domain, :default_context, :dtmf_mode,
      :auto_answer, :transfer_enabled, :credential_ttl, :turn_url, :turn_secret,
      codecs: []
    ).to_h
    permitted['codecs'] = Array(permitted['codecs']).reject(&:blank?)
    permitted['stun_servers'] = parse_lines(params.dig(:jabvox_softphone_config, :stun_servers_text))
    # Un secreto TURN vacío en edición = no cambiarlo.
    permitted.delete('turn_secret') if permitted['turn_secret'].blank? && params[:action] == 'update'
    permitted
  end

  private

  def parse_lines(text)
    text.to_s.split("\n").map(&:strip).reject(&:blank?)
  end
end
