# Autorización de archivos del Drive.
#
# REGLA DE SEGURIDAD (RBAC): solo los ADMINISTRADORES cargan, eliminan, renombran,
# mueven, restauran y purgan. Los agentes y los ROLES PERSONALIZADOS solo pueden VER
# y DESCARGAR — nunca modificar ni eliminar. Un rol personalizado se guarda con
# role=agent (+ custom_role_id), así que `administrator?` es false para él: queda del
# lado de solo-lectura por diseño, sin importar sus permisos personalizados.
#
# El Scope restringe a la cuenta activa y oculta lo no-visible (borrados y filas en
# excedentes/cuarentena) para los no-admin; los admins ven todo lo de su cuenta.
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

  # Cargar, renombrar, mover y borrar: SOLO administradores.
  def create?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
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
