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
  def sso_token
    secret = sso_shared_secret
    if secret.blank?
      # rubocop:disable Rails/I18nLocaleTexts
      return render json: { error: 'SSO no configurado' }, status: :service_unavailable
      # rubocop:enable Rails/I18nLocaleTexts
    end

    frontend = automations_frontend_url
    if frontend.blank?
      # rubocop:disable Rails/I18nLocaleTexts
      return render json: { error: 'URL de Automations no configurada' }, status: :service_unavailable
      # rubocop:enable Rails/I18nLocaleTexts
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
    now = Time.now.to_i
    {
      iss: SSO_ISSUER,
      aud: SSO_AUDIENCE,
      sub: Current.user.id,
      accountId: Current.account.id,
      roles: [Current.account_user.role],
      email: Current.user.email,
      name: Current.user.name,
      nonce: SecureRandom.hex(16),
      iat: now,
      exp: (Time.now + SSO_TTL).to_i
    }
  end

  # Solo admins de la cuenta pueden abrir el modulo.
  def ensure_account_administrator
    return if Current.account_user&.administrator?

    # rubocop:disable Rails/I18nLocaleTexts
    render json: { error: 'Solo los administradores pueden acceder a este modulo' }, status: :forbidden
    # rubocop:enable Rails/I18nLocaleTexts
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
