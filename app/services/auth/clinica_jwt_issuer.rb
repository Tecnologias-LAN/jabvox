# frozen_string_literal: true

# Mints the HS256 JWT that the Clinica module (jabvox-clinica) uses to
# authenticate requests against the core. Claims follow the contract in
# docs/contratos-core.md (section C1) of the jabvox-clinica-integracion repo.
class Auth::ClinicaJwtIssuer
  ALGORITHM = 'HS256'
  ISSUER = 'jabvox-core'
  DEFAULT_EXPIRY = 24.hours

  def self.issue(user:, account:, expires_in: DEFAULT_EXPIRY)
    now = Time.now.to_i
    payload = {
      account_id: account.id,
      sub: user.id.to_s,
      iat: now,
      exp: now + expires_in.to_i,
      iss: ISSUER,
      name: user.name,
      email: user.email
    }
    JWT.encode(payload, secret, ALGORITHM)
  end

  def self.secret
    ENV.fetch('JWT_HS256_SECRET') do
      raise 'JWT_HS256_SECRET is not set. Configure it per environment before issuing Clinica JWTs.'
    end
  end
  private_class_method :secret
end
