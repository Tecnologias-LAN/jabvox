class Api::V1::Accounts::Jabvox::Tasks::BaseController < Api::V1::Accounts::BaseController
  include JabvoxPermissions

  before_action :check_feature_enabled

  private

  def check_feature_enabled
    return if Current.account.feature_enabled?('jabvox_tasks')

    render json: { error: 'El módulo de Tareas no está habilitado para esta cuenta' }, status: :forbidden
  end

  # Gestionar tareas exige el permiso SIEMPRE. Antes bastaba con no tener rol
  # personalizado: el gate salía antes de comprobar nada, así que cualquier agente creaba,
  # editaba y ejecutaba automatizaciones de envío. Ahora un usuario sin rol asignado no
  # pasa, y hay que darle un rol que conceda `jabvox_tasks_manage`.
  #
  # El admin sigue pasando siempre (lo resuelve `user_grants_permission?`).
  def jabvox_gate!(key)
    return if jabvox_can?(key)

    deny_access
  end

  # Borrar es exclusivo del administrador: se lleva por delante tareas enteras —y un
  # tablero o una columna arrastran en cascada todo lo que contienen— así que no se delega
  # en ningún rol, ni siquiera en uno con `jabvox_tasks_manage`.
  def ensure_admin_for_destroy!
    return if Current.account_user&.administrator?

    deny_access
  end

  # Secciones sensibles (webhooks y sus secretos): admin o permiso explícito.
  def ensure_admin
    return if Current.account_user&.administrator?
    return if Current.account_user&.custom_role&.grants?('jabvox_tasks_manage')

    deny_access
  end

  # Un único mensaje para toda denegación: no distingue entre "no tienes rol", "tu rol no
  # concede esto" y "esto es solo de administradores". Decir cuál de los tres es convierte
  # el endpoint en un mapa de la configuración de permisos de la cuenta.
  def deny_access
    render json: { error: 'No tienes permiso para esta acción' }, status: :forbidden
  end
end
