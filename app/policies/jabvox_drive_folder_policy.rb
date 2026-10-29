# Autorización de carpetas del Drive.
#
# REGLA DE SEGURIDAD (RBAC): solo los ADMINISTRADORES crean, renombran, mueven y
# borran carpetas. Los agentes y los ROLES PERSONALIZADOS solo NAVEGAN (ver). Un rol
# personalizado se guarda con role=agent, así que `administrator?` es false para él:
# queda del lado de solo-lectura por diseño.
#
# El aislamiento por cuenta es ESTRICTO: el Scope solo expone carpetas de la cuenta
# activa, y los controllers además buscan dentro de `Current.account.jabvox_drive_folders`.
class JabvoxDriveFolderPolicy < ApplicationPolicy
  def index?
    agent_or_admin?
  end

  def show?
    agent_or_admin?
  end

  # Crear, renombrar, mover y borrar carpetas: SOLO administradores.
  def create?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
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
