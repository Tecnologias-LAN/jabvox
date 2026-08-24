# frozen_string_literal: true

# Administración central de las instancias Hermes por cuenta (Sección 15 del rediseño).
# Solo super admin. Toda operación pasa por el Hermes Provisionador (ProvisionerClient) —
# el super admin NUNCA accede a la BD ni a OVH directamente desde aquí.
#
#   GET  /super_admin/hermes_instances            → lista de cuentas + estado de su Hermes
#   POST /super_admin/hermes_instances/:account_id/provision → aprovisionar/reaprovisionar
#   POST /super_admin/hermes_instances/:account_id/disable   → desactivar
#   POST /super_admin/hermes_instances/:account_id/restart   → reiniciar
#   POST /super_admin/hermes_instances/:account_id/rotate    → rotar credencial de servicio
class SuperAdmin::HermesInstancesController < SuperAdmin::ApplicationController
  def index
    handoffs = JabvoxContextForgeHandoff.all.index_by(&:account_id)
    accounts = Account.where(id: handoffs.keys).or(Account.where(jabvox_ai_chat_enabled_jabvox: true))
    @provisioner = JabvoxHermesProvisioner.instance.safe_summary
    @instances = accounts.map { |acc| instance_summary(acc, handoffs[acc.id]) }
    respond_to do |format|
      format.html # vista ERB del panel
      format.json { render json: { provisioner: @provisioner, instances: @instances } }
    end
  end

  # Conecta el Hermes Aprovisionador GLOBAL (URL + token de servicio). Idempotente.
  # Token en blanco = conservar el actual (no lo sobreescribe con vacío).
  def connect_provisioner
    token = params[:service_token].presence || JabvoxHermesProvisioner.instance.service_token_jabvox
    result = Jabvox::Hermes::ProvisionerConnectService.new(
      base_url: params[:base_url], service_token: token
    ).call
    redirect_back_with(result.success?, result.error, 'Aprovisionador conectado')
  end

  # Liga el aprovisionador global a una cuenta (esa cuenta verá el Chat Aprovisionador).
  def link_account
    provisioner = JabvoxHermesProvisioner.instance
    return redirect_back_with(false, 'Conecta primero el aprovisionador', nil) unless provisioner.connected?

    link = JabvoxHermesProvisionerLink.find_or_initialize_by(account_id: account.id)
    link.hermes_provisioner = provisioner
    link.status_jabvox = 'linked'
    link.save!
    redirect_back_with(true, nil, "Cuenta ##{account.id} ligada")
  end

  def unlink_account
    JabvoxHermesProvisionerLink.find_by(account_id: account.id)&.update(status_jabvox: 'unlinked')
    redirect_back_with(true, nil, "Cuenta ##{account.id} desligada")
  end

  def provision
    result = Jabvox::Hermes::AccountSetupService.new(account).call
    redirect_back_with(result.success?, result.error, "Hermes de la cuenta ##{account.id} aprovisionado")
  end

  def disable
    result = Jabvox::Hermes::ProvisionerClient.new.disable_instance(account)
    account.jabvox_context_forge_handoff&.update(status: 'failed', last_error: 'disabled by admin')
    redirect_back_with(result.success?, result.error, "Hermes de la cuenta ##{account.id} desactivado")
  end

  def restart
    result = Jabvox::Hermes::ProvisionerClient.new.restart_instance(account)
    redirect_back_with(result.success?, result.error, "Hermes de la cuenta ##{account.id} reiniciado")
  end

  def rotate
    identity = JabvoxHermesIdentity.for_account(account)
    identity.rotate_token!
    account.jabvox_context_forge_handoff&.update(scoped_token: identity.service_token.token)
    redirect_back_with(true, nil, "Credencial de la cuenta ##{account.id} rotada")
  end

  private

  def account
    @account ||= Account.find(params[:account_id])
  end

  # Redirige al panel con notice (éxito) o alert (error). Base de las acciones del super admin.
  def redirect_back_with(success, error, notice_msg)
    if success
      redirect_to super_admin_hermes_instances_path, notice: notice_msg
    else
      redirect_to super_admin_hermes_instances_path, alert: (error || 'Operación fallida')
    end
  end

  # Resumen SIN secretos (nunca el token).
  def instance_summary(acc, handoff)
    {
      account_id: acc.id, account_name: acc.name,
      status: handoff&.status || 'pending',
      hermes_url: handoff&.hermes_url,
      provisioned_at: handoff&.provisioned_at,
      last_error: handoff&.last_error,
      mcp_servers: Array(handoff&.mcp_servers)
    }
  end
end
