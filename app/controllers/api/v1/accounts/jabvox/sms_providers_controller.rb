require 'socket'
require 'timeout'

class Api::V1::Accounts::Jabvox::SmsProvidersController < Api::V1::Accounts::Jabvox::BaseController
  jabvox_feature 'jabvox_sms'
  include JabvoxPermissions

  before_action :ensure_module_permission
  before_action :check_authorization
  before_action :set_provider, only: [:show, :update, :destroy, :check_connection]

  def index
    @providers = Current.account.jabvox_sms_providers.order(created_at: :desc)
  end

  def show; end

  def create
    @provider = Current.account.jabvox_sms_providers.create!(provider_params)
    render :show, status: :created
  end

  def update
    attrs = provider_params.to_h
    attrs.delete('api_password') if attrs['api_password'].blank?
    @provider.update!(attrs)
    render :show
  end

  def destroy
    @provider.destroy!
    head :no_content
  end

  # SMS_CHECK_ALLOWED_PORTS: proveedores SMS externos (Bandwidth, Vozip, ...) suelen
  # escuchar en 443/80, no en los puertos de BD del guard de Analytics.
  SMS_CHECK_ALLOWED_PORTS = [443, 80].freeze

  def check_connection
    uri = URI.parse(@provider.base_url)
    port = uri.port || (uri.scheme == 'https' ? 443 : 80)
    guard = Jabvox::Analytics::HostGuardService.new(
      host: uri.host, port: port, allowed_ports: SMS_CHECK_ALLOWED_PORTS
    ).call
    return render json: { connected: false, error: guard.reason }, status: :unprocessable_entity unless guard.allowed?

    render json: { connected: tcp_reachable?(uri.host, port) }
  end

  private

  def check_authorization
    authorize :jabvox_sms_provider
  end

  # Gate solo si el usuario tiene un custom role: sin rol personalizado se
  # conserva el comportamiento histórico (acceso). El admin siempre pasa.
  def ensure_module_permission
    jabvox_authorize_write!('jabvox_sms_manage')
  end

  def set_provider
    @provider = Current.account.jabvox_sms_providers.find(params[:id])
  end

  def provider_params
    params.require(:provider).permit(:name, :base_url, :api_user, :api_password, :active)
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
