class AffiliatePortalController < ActionController::Base
  layout 'affiliate_portal'

  before_action :check_ip_access

  def index; end

  private

  def check_ip_access
    client_ip = Jabvox::IpWhitelistService.extract_client_ip(request)

    if params[:affiliate_slug].present?
      affiliate = JabvoxAffiliate.find_by(portal_slug: params[:affiliate_slug])
      return render_404 unless affiliate
      render_404 unless Jabvox::AffiliateIpWhitelistService.allowed?(affiliate.id, client_ip)
    else
      account = Account.find_by(id: params[:portal_account_id])
      return render_404 unless account
      render_404 unless Jabvox::AffiliateIpWhitelistService.account_allowed?(account.id, client_ip)
    end
  end

  def render_404
    render file: Rails.root.join('public/404.html'), status: :not_found, layout: false
  end
end
