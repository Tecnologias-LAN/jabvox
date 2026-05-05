class Api::V1::Accounts::Jabvox::IpWhitelistsController < Api::V1::Accounts::BaseController
  skip_before_action :check_jabvox_ip_whitelist
  before_action :fetch_entry, only: [:update, :destroy]
  before_action :authorize_entry

  def index
    @entries = Current.account.jabvox_ip_whitelists.ordered
  end

  def create
    @entry = Current.account.jabvox_ip_whitelists.new(entry_params)
    @entry.save!
    Jabvox::IpWhitelistService.invalidate_cache(Current.account.id)
    @requester_blocked = requester_blocked?
  end

  def update
    @entry.update!(entry_params)
    Jabvox::IpWhitelistService.invalidate_cache(Current.account.id)
    @requester_blocked = requester_blocked?
  end

  def destroy
    @entry.destroy!
    Jabvox::IpWhitelistService.invalidate_cache(Current.account.id)
    render json: { requester_blocked: requester_blocked? }
  end

  private

  def fetch_entry
    @entry = Current.account.jabvox_ip_whitelists.find(params[:id])
  end

  def authorize_entry
    authorize @entry || JabvoxIpWhitelist
  end

  def entry_params
    params.require(:jabvox_ip_whitelist).permit(:ip, :is_active, :comment)
  end

  def requester_blocked?
    client_ip = Jabvox::IpWhitelistService.extract_client_ip(request)
    !Jabvox::IpWhitelistService.allowed?(Current.account.id, client_ip)
  end
end
