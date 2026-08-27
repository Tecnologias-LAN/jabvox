# frozen_string_literal: true

# Token firmado (JWT HS256) para el flujo "ir a pagar": identifica la cuenta y el plan
# al saltar de la app a la web de cobro, SIN exponer el account_id en texto plano ni en la
# URL. Expira rápido (15 min) y sirve para un solo propósito (checkout).
#
# La web recibe SOLO el token; para conocer cuenta/plan debe validarlo contra la app
# (endpoint de resolución), nunca lo decodifica por su cuenta.
class Jabvox::Billing::CheckoutTokenService
  ALGORITHM = 'HS256'
  EXPIRY_SECONDS = 15.minutes.to_i
  PURPOSE = 'jabvox_checkout'

  def self.encode(account_id:, plan_id:)
    payload = {
      purpose: PURPOSE,
      acc: account_id,
      plan: plan_id,
      iat: Time.now.to_i,
      exp: Time.now.to_i + EXPIRY_SECONDS
    }
    JWT.encode(payload, secret, ALGORITHM)
  end

  # Devuelve { account_id:, plan_id: } o levanta CheckoutTokenError.
  def self.decode(token)
    decoded = JWT.decode(token, secret, true, { algorithm: ALGORITHM }).first
    raise Jabvox::Billing::CheckoutTokenError, 'purpose_invalid' unless decoded['purpose'] == PURPOSE

    { account_id: decoded['acc'], plan_id: decoded['plan'] }.with_indifferent_access
  rescue JWT::ExpiredSignature
    raise Jabvox::Billing::CheckoutTokenError, 'token_expired'
  rescue JWT::DecodeError
    raise Jabvox::Billing::CheckoutTokenError, 'token_invalid'
  end

  # Secreto dedicado (aislado del resto de firmas de la app).
  def self.secret
    "#{Rails.application.secret_key_base}_jabvox_checkout"
  end
  private_class_method :secret
end
