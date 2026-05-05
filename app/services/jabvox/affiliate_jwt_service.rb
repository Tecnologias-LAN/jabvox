# frozen_string_literal: true

module Jabvox
  class AffiliateAuthError < StandardError; end

  class AffiliateJwtService
    ALGORITHM = 'HS256'
    EXPIRY_SECONDS = 2.hours.to_i

    def self.encode(affiliate_id:, account_id:, ip:)
      payload = {
        sub: affiliate_id,
        acc: account_id,
        ip: ip,
        iat: Time.now.to_i,
        exp: Time.now.to_i + EXPIRY_SECONDS
      }
      JWT.encode(payload, secret, ALGORITHM)
    end

    def self.decode(token)
      decoded = JWT.decode(token, secret, true, { algorithm: ALGORITHM })
      decoded.first.with_indifferent_access
    rescue JWT::ExpiredSignature
      raise AffiliateAuthError, 'token_expired'
    rescue JWT::DecodeError
      raise AffiliateAuthError, 'token_invalid'
    end

    def self.secret
      "#{Rails.application.secret_key_base}_jabvox_affiliates"
    end
    private_class_method :secret
  end
end
