# Registra qué super-admin cambió el usuario de automatizaciones de qué cuenta,
# cuándo y desde qué IP.
#
# Se escribe a mano en vez de marcar el modelo como `audited`: esa gema auditaría
# también cada test_connection y volcaría `api_key_jabvox` a un jsonb sin cifrar.
class Automations::AuditService
  AUDITABLE_ACTION = 'automations_user_changed'.freeze

  def initialize(account:, actor:, request: nil)
    @account = account
    @actor = actor
    @request = request
  end

  def remote_ip
    @request&.remote_ip
  end

  def actor_id
    @actor&.id
  end

  # Se congela el email de ambos usuarios: si esa persona se borra, el id dejaría de
  # resolver. No se registra ningún token, ni completo ni enmascarado.
  def log_user_change(previous_user:, new_user:)
    write_audit(
      previous_user_id: previous_user&.id,
      previous_user_email: previous_user&.email,
      new_user_id: new_user&.id,
      new_user_email: new_user&.email,
      new_user_name: new_user&.name
    )
    log_to_rails_log(previous_user, new_user)
  end

  private

  # `auditable` es la CUENTA para que Enterprise::AuditLog rellene `associated_*` y el
  # cambio salga en el visor por cuenta. `user_type: 'User'` porque SuperAdmin es STI.
  #
  # Todo en un rescue: la auditoría no debe poder tumbar la operación que audita.
  def write_audit(changes)
    return unless audits_available?

    Audited.audit_class.create!(
      auditable: @account,
      action: AUDITABLE_ACTION,
      audited_changes: changes.stringify_keys,
      user_id: actor_id,
      user_type: actor_id ? 'User' : nil,
      username: @actor&.email,
      remote_address: remote_ip,
      request_uuid: @request&.request_id
    )
  rescue StandardError => e
    Rails.logger.warn("[Automations] no se pudo registrar la auditoría del cambio de usuario: #{e.message}")
  end

  # La tabla `audits` es del esquema enterprise: se comprueba para que una instalación
  # sin ella no reciba un 500 al guardar el usuario.
  def audits_available?
    Audited.audit_class.table_exists?
  rescue StandardError
    false
  end

  # Segundo canal a propósito: el log sobrevive a un purgado de `audits`.
  def log_to_rails_log(previous_user, new_user)
    Rails.logger.info(
      "[SuperAdmin] automations user changed for account #{@account.id}: " \
      "#{previous_user&.id || 'ninguno'} -> #{new_user&.id || 'ninguno'} " \
      "(actor_id=#{actor_id}, actor_email=#{@actor&.email}, ip=#{remote_ip})"
    )
  end
end
