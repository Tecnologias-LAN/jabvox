# Central authorization helper for Jabvox modules, backed by Custom Roles.
#
# A capability is granted when the account user is an administrator OR their
# assigned custom role includes the permission key. Users WITHOUT a custom role
# (plain agent/admin) keep their historical behavior: admins pass everything,
# agents get no extra module capabilities — so enabling this system never
# silently removes access from existing users on deploy.
#
# Usage in a controller (include the concern):
#   include JabvoxPermissions
#   before_action -> { jabvox_authorize!('jabvox_contacts_assign') }, only: :bulk_assign
#   scope = jabvox_can?('jabvox_leads_view_all') ? all_leads : own_leads
#
# Usage in a service / anywhere (module method):
#   JabvoxPermissions.user_grants_permission?(account_user, 'jabvox_leads_view_all')
module JabvoxPermissions
  extend ActiveSupport::Concern

  # Shared predicate, callable directly on the module (services, jobs, models).
  # Admins pass everything; otherwise the user's custom role must grant the key.
  # Permisos renombrados al unificar Leads en Contactos. Se consulta también el nombre
  # antiguo para que un rol que no alcanzó la migración (p. ej. una cuenta creada entre el
  # despliegue y el db:migrate) siga concediendo lo mismo en vez de quedarse sin acceso.
  LEGACY_PERMISSION_ALIASES = {
    'jabvox_contacts_view_all' => 'jabvox_leads_view_all',
    'jabvox_contacts_manage' => 'jabvox_leads_manage',
    'jabvox_contacts_delete' => 'jabvox_leads_delete'
  }.freeze

  def self.user_grants_permission?(account_user, key)
    return false if account_user.nil?
    return true if account_user.administrator?

    role = account_user.custom_role
    return false if role.nil?

    role.grants?(key) || role.grants?(LEGACY_PERMISSION_ALIASES[key.to_s]) || false
  end

  # True if the current request's user may exercise `key`.
  def jabvox_can?(key)
    JabvoxPermissions.user_grants_permission?(Current.account_user, key)
  end

  # Renders 403 unless the current user has `key`.
  def jabvox_authorize!(key, message = nil)
    return if jabvox_can?(key)

    render json: { error: message || I18n.t('jabvox.permissions.denied', default: 'You do not have permission for this action.') },
           status: :forbidden
  end

  # Gate that ONLY applies to writes: any GET/HEAD request (index/show and every
  # custom read action — metrics, contacts, summary, history, …) passes for all
  # account members, while state-changing verbs (POST/PATCH/PUT/DELETE) require
  # the module permission. Admins always pass via jabvox_can?. Keying off the
  # HTTP verb (not an action-name list) keeps future read endpoints open by
  # default and every write endpoint gated.
  def jabvox_authorize_write!(key, message = nil)
    return if request.get? || request.head?

    jabvox_authorize!(key, message)
  end
end
