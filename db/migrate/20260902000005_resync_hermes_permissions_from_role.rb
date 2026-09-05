# frozen_string_literal: true

# Los permisos de Hermes se derivan del ROL del usuario (un admin de la cuenta obtiene
# read/create/write/execute/configure; un agente según su custom role). Antes, el agente por
# defecto se creaba con solo 'read', dejando a administradores en modo solo-lectura aunque su
# rol permitiera gestionar. Aquí se re-sincroniza TODA fila existente desde el rol, y se crea
# la fila (derivada del rol) para cada usuario que tenga un agente Hermes pero no tenga fila.
class ResyncHermesPermissionsFromRole < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    # 1. Re-sincroniza las filas ya existentes desde el rol.
    JabvoxHermesUserPermission.find_each do |perm|
      JabvoxHermesUserPermission.sync_from_role!(perm.account_id, perm.user_id)
    rescue StandardError => e
      Rails.logger.warn("[resync-hermes-perms] perm ##{perm.id}: #{e.class} #{e.message}")
    end

    # 2. Crea la fila (derivada del rol) para usuarios con agente Hermes pero sin fila.
    JabvoxHermesAgent.distinct.pluck(:account_id, :user_id).each do |account_id, user_id|
      next if JabvoxHermesUserPermission.exists?(account_id: account_id, user_id: user_id)

      JabvoxHermesUserPermission.sync_from_role!(account_id, user_id)
    rescue StandardError => e
      Rails.logger.warn("[resync-hermes-perms] agent #{account_id}/#{user_id}: #{e.class} #{e.message}")
    end
  end

  def down; end
end
