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
  # code distingue el MOTIVO de una denegación para que la API le dé a Hermes un
  # mensaje accionable (p.ej. 'module_disabled' → "contacta al administrador"):
  #   unknown_tool | not_in_account | mcp_disabled | module_disabled | permission_denied
  Decision = Struct.new(:allowed, :reason, :permission, :code, :feature, keyword_init: true) do
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
    return deny('tool desconocida', code: 'unknown_tool') if spec.nil? # whitelist estricta

    return deny('usuario no pertenece a la cuenta', code: 'not_in_account') unless user_in_account?
    unless account_has_mcp?(spec[:mcp])
      return deny("MCP '#{spec[:mcp]}' no habilitado para la cuenta", code: 'mcp_disabled', feature: spec[:mcp])
    end
    # NIVEL 1.5: el módulo de la tool debe estar HABILITADO en la cuenta. Si el módulo está
    # apagado, la tool no existe para esta cuenta aunque el agente tenga el permiso.
    unless account_has_feature?(spec[:feature])
      return deny("módulo '#{spec[:feature]}' no habilitado para la cuenta",
                  code: 'module_disabled', feature: spec[:feature])
    end

    # NIVEL 2 (rol del agente, PRIORITARIO): el usuario del agente de la cuenta debe tener,
    # por su ROL o CUSTOM ROLE, el permiso real que la acción exige. Si el rol no lo permite,
    # Hermes tampoco (aunque la tabla de permisos de Hermes lo habilite).
    unless role_grants_tool?(spec)
      return deny("el rol del agente no permite esta acción (#{spec[:feature] || 'core'})",
                  code: 'permission_denied', feature: spec[:feature])
    end

    # NIVEL 2.5 (tabla Hermes): además, el permiso de Hermes del usuario debe habilitar la
    # capacidad (read/create/write). Doble candado: lo más restrictivo gana.
    required = spec[:permission]
    return deny("permiso '#{required}' requerido", code: 'permission_denied') unless user_has_permission?(required)

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

  # NIVEL 2 (tabla Hermes): el usuario tiene el permiso granular (fuente de verdad en BD).
  def user_has_permission?(permission)
    JabvoxHermesUserPermission.allows?(@account.id, @user.id, permission)
  end

  # Mapa MÓDULO (feature) → { view:, manage: } con las claves de permiso de rol/custom_role
  # de Jabvox. read exige view; create/write exige manage. Un módulo sin entrada usa CORE.
  MODULE_ROLE_PERMISSIONS = {
    'jabvox_leads'              => { view: 'jabvox_leads_view_all', manage: 'jabvox_leads_edit' },
    'jabvox_kanban'             => { view: 'jabvox_kanban_view_all', manage: 'jabvox_kanban_manage' },
    'jabvox_tasks'              => { view: 'jabvox_tasks_view_all', manage: 'jabvox_tasks_manage' },
    'jabvox_cdr'                => { view: 'jabvox_cdr_view_reports', manage: 'jabvox_cdr_manage' },
    'jabvox_audio_analysis'     => { view: 'jabvox_audio_view_reports', manage: 'jabvox_audio_manage' },
    'jabvox_analytics'          => { view: 'jabvox_analytics_access', manage: 'jabvox_analytics_manage' },
    'jabvox_lead_import'        => { view: 'jabvox_lead_import_manage', manage: 'jabvox_lead_import_manage' },
    'jabvox_data_export'        => { view: 'jabvox_data_export_manage', manage: 'jabvox_data_export_manage' },
    'jabvox_products'           => { view: 'jabvox_products_manage', manage: 'jabvox_products_manage' },
    'jabvox_dialer'             => { view: 'jabvox_dialer_use', manage: 'jabvox_dialer_manage' },
    'jabvox_sms'                => { view: 'jabvox_sms_view', manage: 'jabvox_sms_manage' },
    'jabvox_whatsapp_templates' => { view: 'jabvox_whatsapp_templates_manage', manage: 'jabvox_whatsapp_templates_manage' },
    'jabvox_affiliates'         => { view: 'jabvox_affiliates_manage', manage: 'jabvox_affiliates_manage' },
    'jabvox_customization'      => { view: 'jabvox_custom_data_manage', manage: 'jabvox_custom_data_manage' },
    'jabvox_advanced_automations' => { view: 'jabvox_reports_view', manage: 'jabvox_reports_view' }
  }.freeze

  # Permisos base de Chatwoot para las tools CORE (etiquetas, contactos, conversaciones).
  # Leer es propio de cualquier miembro de la cuenta (view: nil ⇒ no restringe por rol);
  # crear/editar exige poder gestionar conversaciones/contactos.
  CORE_ROLE_PERMISSIONS = { view: nil, manage: 'conversation_manage' }.freeze

  # NIVEL 2 (rol del agente, prioritario). ¿El rol/custom_role del usuario del agente concede
  # el permiso real que la tool exige? Admin concede todo (user_grants_permission? lo resuelve).
  def role_grants_tool?(spec)
    account_user = AccountUser.find_by(account_id: @account.id, user_id: @user.id)
    return false if account_user.nil?

    map = MODULE_ROLE_PERMISSIONS[spec[:feature]] || CORE_ROLE_PERMISSIONS
    key = spec[:permission].to_s == 'read' ? map[:view] : map[:manage]
    return true if key.blank? # sin permiso mapeado ⇒ no restringido por rol

    JabvoxPermissions.user_grants_permission?(account_user, key)
  end

  def deny(reason, code: 'denied', feature: nil)
    Decision.new(allowed: false, reason: reason, code: code, feature: feature)
  end
end
