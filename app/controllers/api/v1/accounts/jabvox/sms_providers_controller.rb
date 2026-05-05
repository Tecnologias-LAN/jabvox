require 'socket'
require 'timeout'

class Api::V1::Accounts::Jabvox::SmsProvidersController < Api::V1::Accounts::Jabvox::BaseController
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

  def check_connection
    uri = URI.parse(@provider.base_url)
    connected = tcp_reachable?(uri.host, uri.port || (uri.scheme == 'https' ? 443 : 80))
    render json: { connected: connected }
  end

  private

  def check_authorization
    authorize :jabvox_sms_provider
  end

  def set_provider
    @provider = Current.account.jabvox_sms_providers.find(params[:id])
  end

  def provider_params
    params.require(:provider).permit(:name, :base_url, :api_user, :api_password, :active)
  end

  def tcp_reachable?(host, port)
    Timeout.timeout(5) { TCPSocket.new(host, port.to_i).close; true }
  rescue Timeout::Error, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError
    false
  end
end
