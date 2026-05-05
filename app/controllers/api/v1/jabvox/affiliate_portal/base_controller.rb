# frozen_string_literal: true

class Api::V1::Jabvox::AffiliatePortal::BaseController < ApplicationController
  include SwitchLocale

  protect_from_forgery with: :null_session

  before_action :authenticate_affiliate!
  before_action :check_ip_whitelist
  around_action :switch_locale_using_account_locale

  private

  def authenticate_affiliate!
    token = extract_bearer_token
    return render_auth_error('token_missing') if token.blank?

    payload = Jabvox::AffiliateJwtService.decode(token)

    token_ip = payload[:ip]
    request_ip = Jabvox::IpWhitelistService.extract_client_ip(request)
    return render_auth_error('ip_mismatch') if token_ip.present? && token_ip != request_ip

    @current_affiliate = JabvoxAffiliate.active.find_by(id: payload[:sub])
    return render_auth_error('affiliate_not_found') unless @current_affiliate

    @current_account = @current_affiliate.account
    Current.account = @current_account
  rescue Jabvox::AffiliateAuthError => e
    render_auth_error(e.message)
  end

  def check_ip_whitelist
    client_ip = Jabvox::IpWhitelistService.extract_client_ip(request)
    return if Jabvox::IpWhitelistService.allowed?(@current_account.id, client_ip)

    render json: { error: 'ip_blocked' }, status: :forbidden
  end

  def render_auth_error(msg)
    render json: { error: msg }, status: :unauthorized
  end

  def extract_bearer_token
    request.headers['Authorization']&.split(' ')&.last
  end
end
