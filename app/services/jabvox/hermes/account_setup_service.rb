# frozen_string_literal: true

# Alta del Hermes de una cuenta cuando se habilita Chat IA (Sección 16 del rediseño).
# Flujo: verificar si existe → si no, PEDIR al Hermes Provisionador que cree la instancia →
# registrar el handoff con la URL/estado devueltos + la identidad de servicio de la cuenta.
#
# El usuario final no ve nada de esto: solo usa Chat IA. Idempotente: si ya está lista, no
# hace nada. Nunca entrega credenciales de BD ni el admin global al Hermes de la cuenta.
class Jabvox::Hermes::AccountSetupService
  Result = Struct.new(:success, :handoff, :error, keyword_init: true) do
    def success? = success
  end

  def initialize(account, provisioner: nil)
    @account = account
    @provisioner = provisioner || Jabvox::Hermes::ProvisionerClient.new
  end

  def call
    handoff = @account.jabvox_context_forge_handoff
    if handoff&.ready_for_chat?
      ensure_default_agent # idempotente: garantiza el agente por defecto aunque ya estuviera lista
      return Result.new(success: true, handoff: handoff)
    end

    provision
  end

  private

  def provision
    handoff = JabvoxContextForgeHandoff.find_or_create_by!(account_id: @account.id)
    handoff.mark_provisioning!
    result = @provisioner.ensure_instance(@account)
    return fail_handoff(handoff, result.error) unless result.success?

    identity = JabvoxHermesIdentity.for_account(@account)
    handoff.mark_ready!(
      hermes_url: result.data['hermes_url'],
      scoped_token: identity.service_token.token, # token de SERVICIO, no admin
      mcp_servers: []
    )
    ensure_default_agent
    Result.new(success: true, handoff: handoff)
  rescue StandardError => e
    fail_handoff(handoff, e.message)
  end

  # Toda cuenta con su Hermes trae 1 agente por defecto, ligado a un administrador de la
  # cuenta, con permisos de lectura. El admin luego crea más agentes con otros permisos.
  def ensure_default_agent
    return if JabvoxHermesAgent.exists?(account_id: @account.id, is_default_jabvox: true)

    admin_user_id = AccountUser.where(account_id: @account.id, role: :administrator).limit(1).pick(:user_id)
    return unless admin_user_id

    JabvoxHermesAgent.create!(
      account_id: @account.id, user_id: admin_user_id, name_jabvox: 'Asistente',
      description_jabvox: 'Agente por defecto del Hermes de la cuenta.',
      is_default_jabvox: true, status_jabvox: 'active'
    )
    # El agente por defecto arranca con permiso de lectura (el admin amplía después).
    perm = JabvoxHermesUserPermission.find_or_initialize_by(account_id: @account.id, user_id: admin_user_id)
    perm.permissions_jabvox = (perm.permissions_list | %w[read]) if perm.permissions_list.empty?
    perm.save! if perm.changed?
  end

  def fail_handoff(handoff, error)
    handoff&.mark_failed!(error)
    Result.new(success: false, error: error)
  end
end
