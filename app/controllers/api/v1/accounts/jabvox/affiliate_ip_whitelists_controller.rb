class Api::V1::Accounts::Jabvox::AffiliateIpWhitelistsController < Api::V1::Accounts::BaseController
  before_action :fetch_affiliate
  before_action :fetch_entry, only: [:update, :destroy]

  def index
    entries = @affiliate.jabvox_affiliate_ip_whitelists.ordered
    render json: entries.map { |e| entry_json(e) }
  end

  def create
    @entry = @affiliate.jabvox_affiliate_ip_whitelists.new(entry_params)
    @entry.save!
    Jabvox::AffiliateIpWhitelistService.invalidate_cache(@affiliate.id)
    render json: entry_json(@entry), status: :created
  end

  def update
    @entry.update!(entry_params)
    Jabvox::AffiliateIpWhitelistService.invalidate_cache(@affiliate.id)
    render json: entry_json(@entry)
  end

  def destroy
    @entry.destroy!
    Jabvox::AffiliateIpWhitelistService.invalidate_cache(@affiliate.id)
    render json: { success: true }
  end

  private

  def fetch_affiliate
    @affiliate = Current.account.jabvox_affiliates.find(params[:affiliate_id])
  end

  def fetch_entry
    @entry = @affiliate.jabvox_affiliate_ip_whitelists.find(params[:id])
  end

  def entry_params
    params.require(:jabvox_affiliate_ip_whitelist).permit(:ip, :is_active, :comment)
  end

  def entry_json(entry)
    { id: entry.id, ip: entry.ip, is_active: entry.is_active, comment: entry.comment, created_at: entry.created_at }
  end
end
