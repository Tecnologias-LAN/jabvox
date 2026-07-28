# Emisor de SSO + comprobación de permisos para el iframe embebido del módulo
# "Automatizaciones Avanzadas". Jabvox firma un JWT de corta vida (5 min) que el
# motor de Automation valida para crear su propia sesión. El secreto compartido
# JAMAS viaja al navegador ni a los logs.
class Api::V1::Accounts::Jabvox::AdvancedAutomationsController < Api::V1::Accounts::Jabvox::BaseController
  jabvox_feature 'jabvox_advanced_automations'

  before_action :ensure_account_administrator

  SSO_ISSUER = 'jabvox'.freeze
  SSO_AUDIENCE = 'automation-engine'.freeze
  SSO_TTL = 5.minutes

  # POST /api/v1/accounts/:account_id/jabvox/advanced_automations/sso_token
  # Devuelve { url } con el JWT en el query. No expone el secreto.
  # Los dos mensajes nombran la clave que falta y donde se rellena: este 503 lo
  # ve un administrador de la plataforma, no un usuario final, y sin el nombre
  # concreto no hay forma de saber cual de las dos configuraciones falta.
  def sso_token
    secret = sso_shared_secret
    if secret.blank?
      return render json: { error: 'Falta AUTOMATIONS_SSO_SECRET en Super Admin > Jabvox Automations' },
                    status: :service_unavailable
    end

    frontend = automations_frontend_url
    if frontend.blank?
      return render json: { error: 'Falta AUTOMATIONS_FRONTEND_URL (URL publica del iframe) en Super Admin > Jabvox Automations' },
                    status: :service_unavailable
    end

    token = JWT.encode(sso_claims, secret, 'HS256')
    render json: { url: "#{frontend.chomp('/')}/embed?sso=#{token}&theme=#{sanitized_theme}" }
  end

  # GET /api/v1/accounts/:account_id/jabvox/advanced_automations/permissions_check
  # El iframe (vía su padre) consulta si el usuario sigue siendo admin y el
  # modulo activo, para que Automation cierre la sesion si se perdieron permisos.
  def permissions_check
    render json: { ok: still_authorized? }
  end

  private

  def sso_claims
    # `Time.current` (zona de la app) en vez de `Time.now` (zona del sistema):
    # iat/exp son epoch UTC y el motor de Automations los valida contra su propio
    # reloj, asi que un desfase de zona entre Rails y el sistema recortaria la
    # vida util del token o lo haria nacer caducado.
    #
    # Se toma UN solo instante y se reutiliza: antes `exp` volvia a llamar a
    # `Time.now`, de modo que iat y exp se median en momentos distintos y la
    # ventana real no era exactamente SSO_TTL.
    now = Time.current
    {
      iss: SSO_ISSUER,
      aud: SSO_AUDIENCE,
      sub: Current.user.id,
      accountId: Current.account.id,
      roles: [Current.account_user.role],
      email: Current.user.email,
      name: Current.user.name,
      nonce: SecureRandom.hex(16),
      iat: now.to_i,
      exp: (now + SSO_TTL).to_i
    }
  end

  # Solo admins de la cuenta pueden abrir el modulo.
  def ensure_account_administrator
    return if Current.account_user&.administrator?

    render json: { error: 'Solo los administradores pueden acceder a este modulo' }, status: :forbidden
  end

  def still_authorized?
    Current.account_user&.administrator? &&
      Current.account.feature_enabled?('jabvox_advanced_automations')
  end

  # 'light' | 'dark' — cualquier otro valor cae en 'light'.
  def sanitized_theme
    params[:theme].to_s == 'dark' ? 'dark' : 'light'
  end

  def sso_shared_secret
    GlobalConfigService.load('AUTOMATIONS_SSO_SECRET', nil).to_s.strip
  end

  def automations_frontend_url
    GlobalConfigService.load('AUTOMATIONS_FRONTEND_URL', nil).to_s.strip
  end
end
