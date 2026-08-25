# frozen_string_literal: true

# Autoridad de seguridad de Hermes. Decide si una (cuenta, usuario, tool) puede ejecutarse.
# El LLM NUNCA es la autoridad: aunque el modelo pida ejecutar una tool, esto la rechaza si
# falta cualquiera de las dos condiciones.
#
# Doble autorización:
#   NIVEL 1 (cuenta): la cuenta tiene habilitado el MCP de la tool (mcps habilitados en el
#            handoff, o el core siempre disponible).
#   NIVEL 2 (usuario): el usuario tiene el permiso granular que la tool requiere.
#
# Además valida que la tool exista en el registro (whitelist estricta: anti tool-injection)
# y que el usuario pertenezca a la cuenta (anti IDOR / cross-account).
class Jabvox::Hermes::Authorizer
  Decision = Struct.new(:allowed, :reason, :permission, keyword_init: true) do
    def allowed? = allowed
  end

  # MCPs INTERNOS de Jabvox: son las áreas nativas de la cuenta (etiquetas, contactos, dialer,
  # leads, gestiones, sms, analítica...). No requieren aprovisionamiento externo — su acceso
  # real lo controla el gate de MÓDULO (NIVEL 1.5, feature_enabled?) + el permiso del agente.
  # Los MCPs externos (creados por el aprovisionador, p.ej. analytics_db_49) sí se validan
  # contra el handoff en account_has_mcp?.
  CORE_MCPS = %w[
    jabvox_core jabvox_dialer jabvox_leads jabvox_management jabvox_sms analytics
  ].freeze

  def initialize(account:, user:)
    @account = account
    @user = user
  end

  # ¿Puede este usuario ejecutar esta tool en esta cuenta? Devuelve una Decision.
  def authorize(tool_name)
    spec = Jabvox::Hermes::ToolRegistry.find(tool_name)
    return deny('tool desconocida') if spec.nil? # whitelist estricta

    return deny('usuario no pertenece a la cuenta') unless user_in_account?
    return deny("MCP '#{spec[:mcp]}' no habilitado para la cuenta") unless account_has_mcp?(spec[:mcp])
    # NIVEL 1.5: el módulo de la tool debe estar HABILITADO en la cuenta. Si el módulo está
    # apagado, la tool no existe para esta cuenta aunque el agente tenga el permiso.
    return deny("módulo '#{spec[:feature]}' no habilitado para la cuenta") unless account_has_feature?(spec[:feature])

    required = spec[:permission]
    return deny("permiso '#{required}' requerido") unless user_has_permission?(required)

    Decision.new(allowed: true, reason: 'ok', permission: required)
  end

  # Lista de tools que este usuario PUEDE usar (para exponer SOLO esas al LLM).
  def allowed_tools
    Jabvox::Hermes::ToolRegistry.all.keys.select { |name| authorize(name).allowed? }
  end

  private

  # NIVEL 0: el usuario debe pertenecer a la cuenta (evita cross-account por IDs manipulados).
  def user_in_account?
    AccountUser.exists?(account_id: @account.id, user_id: @user.id)
  end

  # NIVEL 1: la cuenta tiene el MCP habilitado (core siempre; el resto según handoff).
  def account_has_mcp?(mcp)
    return true if CORE_MCPS.include?(mcp)

    handoff = @account.jabvox_context_forge_handoff
    return false unless handoff

    Array(handoff.mcp_servers).map { |m| m.is_a?(Hash) ? m['kind'] : m.to_s }.include?(mcp)
  end

  # NIVEL 1.5: el módulo (jabvox_feature) de la tool está habilitado en la cuenta. Una tool
  # sin módulo declarado (feature nil o 'core') no requiere gate — es funcionalidad base.
  def account_has_feature?(feature)
    return true if feature.blank? || feature == 'core'

    @account.feature_enabled?(feature)
  end

  # NIVEL 2: el usuario tiene el permiso granular (fuente de verdad en BD, no el prompt).
  def user_has_permission?(permission)
    JabvoxHermesUserPermission.allows?(@account.id, @user.id, permission)
  end

  def deny(reason)
    Decision.new(allowed: false, reason: reason)
  end
end
