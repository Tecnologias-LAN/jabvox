# Autorización del historial de auditoría del Drive. Solo administradores: la bitácora
# de quién hizo qué es información sensible de gobernanza, no para agentes.
class JabvoxDriveAuditLogPolicy < ApplicationPolicy
  def index?
    @account_user.administrator?
  end

  class Scope < Scope
    def resolve
      return scope.none unless account_user.administrator?

      scope.where(account_id: account.id)
    end
  end
end
