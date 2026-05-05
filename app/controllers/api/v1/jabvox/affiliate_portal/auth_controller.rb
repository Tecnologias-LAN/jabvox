# frozen_string_literal: true

class Api::V1::Jabvox::AffiliatePortal::AuthController < ApplicationController
  protect_from_forgery with: :null_session

  # POST /api/v1/jabvox/affiliate_portal/auth/login
  def login
    affiliate = JabvoxAffiliate.find_by(account_code: params[:account_code])

    unless affiliate&.active? &&
           affiliate.portal_slug == params[:affiliate_slug].to_s &&
           ActiveSupport::SecurityUtils.secure_compare(affiliate.auth_token, params[:auth_token].to_s)
      return render json: { error: 'invalid_credentials' }, status: :unauthorized
    end

    unless affiliate.account.jabvox_affiliates_enabled_jabvox?
      return render json: { error: 'module_disabled' }, status: :forbidden
    end

    client_ip = Jabvox::IpWhitelistService.extract_client_ip(request)
    unless Jabvox::AffiliateIpWhitelistService.allowed?(affiliate.id, client_ip)
      return render json: { error: 'ip_blocked' }, status: :forbidden
    end

    token = Jabvox::AffiliateJwtService.encode(
      affiliate_id: affiliate.id,
      account_id: affiliate.account_id,
      ip: client_ip
    )

    render json: {
      token: token,
      expires_in: Jabvox::AffiliateJwtService::EXPIRY_SECONDS,
      affiliate: { id: affiliate.id, name: affiliate.name }
    }
  end
end
