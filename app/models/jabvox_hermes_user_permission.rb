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

  # Deriva los permisos de Hermes A PARTIR DEL ROL del usuario en la cuenta. Esta es la
  # fuente: el rol define lo que el usuario puede hacer, y esos permisos se ESCRIBEN aquí
  # (sync_from_role!). La autorización se basa solo en esta tabla.
  #   - Administrador de la cuenta ⇒ read, create, write, execute, configure (nunca delete).
  #   - Agente/custom role ⇒ 'read' siempre; 'create'+'write' si su rol gestiona algo
  #     (tiene conversation_manage/contact_manage o cualquier permiso jabvox_*_manage/_edit).
  # Nunca concede 'admin' (esa palabra es solo un atajo interno) ni 'delete'.
  def self.permissions_for_role(account_user)
    return [] if account_user.nil?
    return %w[read create write execute configure] if account_user.administrator?

    perms = %w[read]
    perms += %w[create write] if role_can_manage?(account_user)
    perms
  end

  # ¿El rol/custom_role del usuario permite gestionar (crear/editar) algo? Base Chatwoot o
  # cualquier capacidad Jabvox de gestión/acción. Reconoce los sufijos de GESTIÓN
  # (manage/edit) y también los de ACCIÓN disruptiva que implican crear/escribir en su
  # módulo (send = enviar masivo, use = usar/operar el módulo, assign = asignar). NO
  # cuenta los de solo lectura (view/view_all/view_reports/access), que quedan en 'read'.
  MANAGE_SUFFIXES = /\Ajabvox_.*(manage|edit|send|use|assign)\z/
  def self.role_can_manage?(account_user)
    role = account_user.custom_role
    return false if role.nil?

    keys = Array(role.permissions)
    keys.include?('conversation_manage') || keys.include?('contact_manage') ||
      keys.any? { |k| k.to_s.match?(MANAGE_SUFFIXES) }
  end

  # Escribe en la tabla los permisos derivados del rol del usuario (idempotente). Se llama al
  # ligar un agente y cuando cambia el rol. Devuelve el registro.
  def self.sync_from_role!(account_id, user_id)
    account_user = AccountUser.find_by(account_id: account_id, user_id: user_id)
    return nil if account_user.nil?

    derived = permissions_for_role(account_user)
    record = find_or_initialize_by(account_id: account_id, user_id: user_id)
    record.permissions_jabvox = derived
    record.save!
    record
  end

  # ¿El usuario tiene el permiso dado en la cuenta? (fuente de verdad de autorización)
  #
  # Los permisos se DERIVAN DEL ROL del usuario (permissions_for_role). La tabla es la
  # materialización de esa derivación: si la fila existe se usa; si no existe (o el usuario
  # es admin), se cae al cálculo desde el rol, de modo que un admin nunca queda bloqueado
  # por falta de fila. Borrar jamás se concede, por ninguna vía.
  def self.allows?(account_id, user_id, permission)
    permission = permission.to_s
    return false if FORBIDDEN.include?(permission) # borrar jamás

    perms = effective_permissions(account_id, user_id)
    return true if perms.include?(permission)

    # 'admin' implica todo lo concedible EXCEPTO borrar.
    perms.include?('admin') && ADMIN_IMPLIES.include?(permission)
  end

  # Permisos efectivos: la fila almacenada si existe; si no, los derivados del rol. Un admin
  # de la cuenta obtiene siempre al menos lo que su rol implica (no depende de tener fila).
  def self.effective_permissions(account_id, user_id)
    stored = where(account_id: account_id, user_id: user_id).first
    return stored.permissions_list if stored

    account_user = AccountUser.find_by(account_id: account_id, user_id: user_id)
    permissions_for_role(account_user)
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
