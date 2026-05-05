module JabvoxIpWhitelistCheck
  extend ActiveSupport::Concern

  private

  # Used by Api::V1::Accounts::BaseController (runs after current_account is set)
  def check_jabvox_ip_whitelist
    return unless Current.account

    client_ip = Jabvox::IpWhitelistService.extract_client_ip(request)
    return if Jabvox::IpWhitelistService.allowed?(Current.account.id, client_ip)

    render json: { error: 'ip_blocked' }, status: :not_found
  end

  # Used by DashboardController (parses account_id from the URL path)
  # If we can identify another accessible account via the session cookie, redirect there immediately.
  # Otherwise let the page load — the JS api interceptor (handleIpBlock) will call /auth/validate_token,
  # find an accessible account, and redirect without ever reaching the login screen.
  def check_jabvox_ip_for_account_page
    match = request.path.match(%r{/app/accounts/(\d+)/})
    return unless match

    account_id = match[1].to_i
    client_ip = Jabvox::IpWhitelistService.extract_client_ip(request)
    return if Jabvox::IpWhitelistService.allowed?(account_id, client_ip)

    user_id = cookies.signed['user.id']
    return unless user_id.present?

    user = User.find_by(id: user_id)
    return unless user

    accessible = user.accounts.where.not(id: account_id).find do |account|
      Jabvox::IpWhitelistService.allowed?(account.id, client_ip)
    end
    redirect_to "/app/accounts/#{accessible.id}/", allow_other_host: false if accessible
  end

end
