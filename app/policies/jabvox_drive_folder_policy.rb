# Autorización de carpetas del Drive.
#
# Convención del módulo (ver ContactPolicy): administradores todo; los agentes
# pueden navegar y crear/renombrar/mover carpetas, pero no borrar. El aislamiento
# por cuenta es ESTRICTO: el Scope solo expone carpetas de la cuenta activa, y los
# controllers además buscan dentro de `Current.account.jabvox_drive_folders`.
class JabvoxDriveFolderPolicy < ApplicationPolicy
  def index?
    agent_or_admin?
  end

  def show?
    agent_or_admin?
  end

  def create?
    agent_or_admin?
  end

  def update?
    agent_or_admin?
  end

  def destroy?
    @account_user.administrator?
  end

  private

  def agent_or_admin?
    @account_user.administrator? || @account_user.agent?
  end

  class Scope < Scope
    def resolve
      scope.where(account_id: account.id)
    end
  end
end
