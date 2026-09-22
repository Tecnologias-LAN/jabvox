# frozen_string_literal: true

# Configuración del Hermes APROVISIONADOR global (un agente) y de qué cuentas lo usan.
# Solo super admin. El aprovisionador es UN AGENTE Hermes normal (4 datos); las cuentas
# ligadas ven el "Chat Aprovisionador", que habla con ese agente. No fabrica Hermes por
# cuenta (eso es el Chat IA por cuenta, gestionado aparte en Ajustes → Chat IA).
#
#   GET  /super_admin/hermes_instances                       → agente + cuentas ligadas
#   POST /super_admin/hermes_instances/connect_provisioner   → conectar/actualizar el agente
#   POST /super_admin/hermes_instances/:account_id/link_account   → activar en una cuenta
#   POST /super_admin/hermes_instances/:account_id/unlink_account → desactivar en una cuenta
class SuperAdmin::HermesInstancesController < SuperAdmin::ApplicationController
  def index
    linked_account_ids = JabvoxHermesProvisionerLink.where(status_jabvox: 'linked').pluck(:account_id)
    accounts = Account.where(id: linked_account_ids).or(Account.where(jabvox_ai_chat_enabled_jabvox: true))
    @provisioner = JabvoxHermesProvisioner.instance.safe_summary
    linked = linked_account_ids.to_set
    @instances = accounts.map { |acc| instance_summary(acc, linked.include?(acc.id)) }
    respond_to do |format|
      format.html # vista ERB del panel
      format.json { render json: { provisioner: @provisioner, instances: @instances } }
    end
  end

  # Conecta/actualiza el Hermes Aprovisionador GLOBAL ÚNICO como un agente: nombre visible,
  # nombre del agente en Hermes, URL del agente y token. El token en blanco = conservar el
  # actual (no se sobreescribe con vacío).
  def connect_provisioner
    current = JabvoxHermesProvisioner.instance
    token = params[:service_token].presence || current.service_token_jabvox
    result = Jabvox::Hermes::ProvisionerConnectService.new(
      base_url: params[:base_url], service_token: token,
      name: params[:name], hermes_agent_name: params[:hermes_agent_name]
    ).call
    redirect_back_with(result.success?, result.error, 'Aprovisionador conectado')
  end

  # Activa el aprovisionador en una cuenta (esa cuenta verá el Chat Aprovisionador).
  def link_account
    provisioner = JabvoxHermesProvisioner.instance
    return redirect_back_with(false, 'Conecta primero el aprovisionador', nil) unless provisioner.connected?

    link = JabvoxHermesProvisionerLink.find_or_initialize_by(account_id: account.id)
    link.hermes_provisioner = provisioner
    link.status_jabvox = 'linked'
    link.save!
    redirect_back_with(true, nil, "Cuenta ##{account.id} activada")
  end

  def unlink_account
    JabvoxHermesProvisionerLink.find_by(account_id: account.id)&.update(status_jabvox: 'unlinked')
    redirect_back_with(true, nil, "Cuenta ##{account.id} desactivada")
  end

  # Allowlist de IPs desde las que el Hermes de ESTA cuenta puede ejecutar acciones. La
  # conexión se busca dentro de la cuenta (nunca por id global), así que no se puede tocar
  # la de otra cuenta desde aquí.
  def update_allowed_ips
    conn = account.jabvox_hermes_connections.find_by(id: params[:connection_id])
    return redirect_back_with(false, 'Conexión no encontrada', nil) if conn.nil?

    ips = params[:allowed_ips].to_s.split(',').map(&:strip).reject(&:blank?)
    if conn.update(allowed_ips_jabvox: ips)
      redirect_back_with(true, nil, "IPs actualizadas para «#{conn.name_jabvox}»")
    else
      redirect_back_with(false, conn.errors.full_messages.to_sentence, nil)
    end
  end

  # Rota el action_token (Hermes → Jabvox) de una conexión: genera uno nuevo e invalida el
  # anterior de inmediato. La conexión se busca DENTRO de la cuenta (nunca por id global). El
  # token nuevo se muestra una vez en el panel (flash) para copiarlo al gateway de Hermes.
  def rotate_action_token
    conn = account.jabvox_hermes_connections.find_by(id: params[:connection_id])
    return redirect_back_with(false, 'Conexión no encontrada', nil) if conn.nil?

    conn.rotate_action_token!
    flash[:revealed_token] = { 'connection_id' => conn.id, 'token' => conn.action_token_jabvox }
    redirect_back_with(true, nil, "Token renovado para «#{conn.name_jabvox}». Cópialo ahora.")
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

  # Estado de una cuenta frente al aprovisionador: si está activada (ligada), y las
  # conexiones Hermes de esa cuenta con su allowlist de IPs (desde qué origen puede ese
  # Hermes ejecutar acciones sobre la cuenta).
  def instance_summary(acc, linked)
    {
      account_id: acc.id, account_name: acc.name, linked: linked,
      connections: acc.jabvox_hermes_connections.order(:name_jabvox).map do |conn|
        # Este es el panel del super admin (autenticado): a diferencia de la API de cuenta,
        # aquí SÍ se muestra el action_token para poder configurarlo/rotarlo en el gateway.
        { id: conn.id, name: conn.name_jabvox, base_url: conn.base_url_jabvox,
          allowed_ips: Array(conn.allowed_ips_jabvox),
          action_token: conn.action_token_jabvox, has_action_token: conn.action_token_jabvox.present? }
      end
    }
  end
end
