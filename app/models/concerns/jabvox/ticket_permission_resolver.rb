# Resuelve el rol de un usuario en el helpdesk central de tickets a partir de su
# rol en la CUENTA GESTORA (configurada en super admin):
#   staff    = administrador de la cuenta gestora → ve/gestiona TODOS los tickets
#   resolver = agente de la cuenta gestora → gestiona los tickets asignados a él
#   requester = cualquier otro usuario → solo sus propios tickets
#
# Se instancia con el user; consulta la cuenta gestora vía JabvoxTicketHelpdeskConfig.
class Jabvox::TicketPermissionResolver
  def initialize(user)
    @user = user
  end

  def manager_account
    @manager_account ||= JabvoxTicketHelpdeskConfig.manager_account
  end

  def config
    @config ||= JabvoxTicketHelpdeskConfig.current
  end

  # Knob: si la config del helpdesk pone la visibilidad del resolver en "bandeja
  # completa", un resolver ve/gestiona todos los tickets, no solo los asignados.
  def resolver_sees_all?
    (resolver? && config&.resolver_full_visibility?) || false
  end

  # AccountUser del usuario en la cuenta gestora (nil si no pertenece a ella).
  def manager_account_user
    return nil if @user.nil? || manager_account.nil?

    @manager_account_user ||= manager_account.account_users.find_by(user_id: @user.id)
  end

  # Staff = administrador de la cuenta gestora. Ve y gestiona todo.
  def staff?
    manager_account_user&.administrator? || false
  end

  # Resolver = staff, o agente de la cuenta gestora (gestiona lo asignado a él).
  def resolver?
    return true if staff?

    manager_account_user&.agent? || false
  end

  # Manager = staff (administra categorías y configuración).
  def manager?
    staff?
  end

  def role_key
    return 'manager' if manager?
    return 'resolver' if resolver?

    'requester'
  end

  # Hash para el endpoint de permisos del frontend.
  def to_permissions
    { staff: staff?, resolver: resolver?, manager: manager?,
      resolver_sees_all: resolver_sees_all? }
  end
end
