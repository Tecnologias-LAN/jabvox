# Autorización de archivos del Drive.
#
# Convención del módulo (ver ContactPolicy): administradores todo; los agentes
# pueden listar, ver, descargar, subir, renombrar y mover; solo los admins borran.
# El Scope restringe a la cuenta activa y oculta lo no-visible (borrados y filas en
# excedentes/cuarentena) para los agentes; los admins ven todo lo de su cuenta.
class JabvoxDriveFilePolicy < ApplicationPolicy
  def index?
    agent_or_admin?
  end

  def show?
    agent_or_admin?
  end

  # Descarga del contenido (redirección a presigned de vida corta o stream).
  def download?
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

  # Papelera: listar, restaurar y eliminar definitivamente — solo administradores.
  def trash?
    @account_user.administrator?
  end

  def restore?
    @account_user.administrator?
  end

  def purge?
    @account_user.administrator?
  end

  private

  def agent_or_admin?
    @account_user.administrator? || @account_user.agent?
  end

  class Scope < Scope
    def resolve
      base = scope.where(account_id: account.id).kept
      return base if account_user.administrator?

      # Los agentes no ven excedentes ni cuarentena: solo lo disponible.
      base.visible
    end
  end
end
