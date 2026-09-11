# frozen_string_literal: true

# Base de la API Provisioner (Hermes → Jabvox). Superficie administrativa altamente
# privilegiada: cada petición revalida TODO desde cero (token, IP, firma, anti-replay, sesión
# única) vía RequestGuard, sin caché. Endpoint público (ActionController::API, sin sesión web
# ni CSRF): la autenticación es 100% por token firmado.
class Api::Provisioner::BaseController < ActionController::API
  before_action :guard_request!

  private

  # Autentica UNA sola vez por petición (el anti-replay consume el nonce; no repetir).
  def guard_request!
    result = Jabvox::Provisioner::RequestGuard.new(request).authenticate
    unless result.ok?
      JabvoxProvisionerAuditLog.record!(
        token_id: nil, resource: nil, action: nil, outcome: 'denied',
        reason: result.code, ip: request.remote_ip, params: {}, status: result.status
      )
      return render json: { error: result.code }, status: result.status
    end

    @guarded_token = result.token
    @guarded_session = result.session
    @signed_body = result.body || {}
  end

  attr_reader :guarded_token, :guarded_session, :signed_body

  def client_ip
    request.remote_ip.to_s
  end
end
