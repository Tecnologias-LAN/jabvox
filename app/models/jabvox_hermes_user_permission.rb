# Permisos GRANULARES de un usuario dentro de una cuenta para las acciones de Hermes.
#
# La autorización NUNCA depende del prompt ni del LLM: el backend consulta estos permisos
# antes de exponer o ejecutar cualquier tool. El usuario no puede auto-otorgarse permisos
# (solo un admin de la cuenta / super admin los edita).
# == Schema Information
#
# Table name: jabvox_hermes_user_permissions
#
#  id                 :bigint           not null, primary key
#  permissions_jabvox :jsonb            not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  user_id            :bigint           not null
#
# Indexes
#
#  idx_hermes_user_perms_unique                        (account_id,user_id) UNIQUE
#  index_jabvox_hermes_user_permissions_on_account_id  (account_id)
#  index_jabvox_hermes_user_permissions_on_user_id     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxHermesUserPermission < ApplicationRecord
  # Permisos concedibles a un agente de Hermes. POLÍTICA ESTRICTA: NO existe 'delete'.
  # El token entregado a Hermes solo puede LEER, CREAR y EDITAR. Borrar registros de
  # Jabvox está prohibido a nivel de arquitectura (no hay permiso ni ruta para ello).
  PERMISSIONS = %w[read create write execute configure admin].freeze

  # 'admin' implica todos los permisos EXCEPTO borrar. Nunca se concede la capacidad de
  # borrar por ninguna vía, ni siquiera admin. Fuente única de "qué implica admin".
  ADMIN_IMPLIES = %w[read create write execute configure].freeze

  # Permiso que jamás puede otorgarse (defensa en profundidad para la capa de dispatch).
  FORBIDDEN = %w[delete destroy].freeze

  belongs_to :account
  belongs_to :user

  validate :permissions_are_valid

  # Permisos efectivos de un usuario en una cuenta (array de strings). Sin registro = [].
  def self.granted_for(account_id, user_id)
    where(account_id: account_id, user_id: user_id).first&.permissions_list || []
  end

  # ¿El usuario tiene el permiso dado en la cuenta? (fuente de verdad de autorización)
  def self.allows?(account_id, user_id, permission)
    permission = permission.to_s
    return false if FORBIDDEN.include?(permission) # borrar jamás, por ninguna vía

    perms = granted_for(account_id, user_id)
    return true if perms.include?(permission)

    # 'admin' implica todo lo concedible EXCEPTO borrar.
    perms.include?('admin') && ADMIN_IMPLIES.include?(permission)
  end

  def permissions_list
    Array(permissions_jabvox).map(&:to_s)
  end

  private

  def permissions_are_valid
    invalid = permissions_list - PERMISSIONS
    return if invalid.empty?

    errors.add(:permissions_jabvox, "permisos inválidos: #{invalid.join(', ')}")
  end
end
