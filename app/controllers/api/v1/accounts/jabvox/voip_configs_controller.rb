require 'socket'
require 'timeout'

class Api::V1::Accounts::Jabvox::VoipConfigsController < Api::V1::Accounts::Jabvox::BaseController
  before_action :check_authorization

  def show
    @config = Current.account.jabvox_voip_config || JabvoxVoipConfig.new
  end

  def update
    @config = Current.account.jabvox_voip_config ||
              Current.account.build_jabvox_voip_config
    params[:config].delete(:password) if params[:config][:password].blank?
    @config.update!(config_params)
    render :show
  end

  def status
    config = Current.account.jabvox_voip_config
    render json: { connected: false, message: 'No configuration found' } and return unless config&.host.present?

    connected = tcp_reachable?(config.host, config.port)
    message = connected ? 'Conexión con Asterisk activa y configuración válida.' : 'No se pudo conectar al servidor de Asterisk.'
    render json: { connected: connected, message: message }
  end

  def originate
    config = Current.account.jabvox_voip_config
    render json: { success: false, message: 'No VoIP configuration found' } and return unless config&.host.present?

    phone = params[:phone].to_s.strip
    if phone.blank? || phone == '***'
      contact = Current.account.contacts.find_by(id: params[:contact_id])
      phone = contact&.phone_number.to_s.strip
    end
    extension = params[:extension].to_s.strip

    if phone.blank? || extension.blank?
      render json: { success: false, message: 'Phone and extension are required' }, status: :unprocessable_entity and return
    end

    result = Jabvox::VoipService.new(config).originate(
      extension: extension,
      phone: phone,
      caller_id: params[:caller_id]
    )
    render json: result
  end

  private

  def check_authorization
    authorize :jabvox_voip_config
  end

  def config_params
    params.require(:config).permit(:host, :port, :username, :password, :context, :dialer_context, :dialer_trunk, :dialer_caller_id)
  end

  def tcp_reachable?(host, port)
    Timeout.timeout(5) do
      TCPSocket.new(host, port.to_i).close
      true
    end
  rescue Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError
    false
  end
end
