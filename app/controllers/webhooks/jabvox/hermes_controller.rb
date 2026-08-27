# frozen_string_literal: true

# Callback del Hermes Aprovisionador hacia Jabvox.
#
# Cuando el Aprovisionador termina de levantar el Hermes de una cuenta (o falla al hacerlo),
# notifica aquí para que Jabvox marque el handoff de esa cuenta como operativo (o fallido).
# A partir de ese momento el Chat IA de la cuenta puede usar su Hermes.
#
# Endpoint PÚBLICO (ActionController::API, sin CSRF) pero blindado:
#   1) Verifica un token compartido (HERMES_PROVISIONER_CALLBACK_SECRET) con comparación
#      en tiempo constante. Sin token válido no se procesa nada.
#   2) La cuenta debe existir. El account_id lo fija el handoff, nunca escala a otra cuenta.
#   3) Solo puede pasar el handoff a 'ready' o 'failed' con los datos de conexión del Hermes
#      de ESA cuenta. Nunca borra ni toca otra cuenta.
#
# El Aprovisionador (y SOLO él, es de confianza y corre en la VM autorizada a la DB) puede
# además pedir las conexiones de DB de una cuenta para CREAR el MCP de analítica de esa
# cuenta. El Hermes de la cuenta nunca recibe credenciales: consume la DB por ese MCP.
#
# Rutas:
#   POST /webhooks/jabvox/hermes/provisioned                        -> provisioned
#   GET  /webhooks/jabvox/hermes/data_sources/:account_id           -> data_sources (sin secretos)
#   GET  /webhooks/jabvox/hermes/data_sources/:account_id/:id/credentials -> credentials (con secretos)
class Webhooks::Jabvox::HermesController < ActionController::API
  before_action :authenticate_provisioner!
  before_action :require_linked_account!, only: %i[data_sources credentials]

  # Payload esperado desde el Aprovisionador:
  #   { account_id:, status: "ready"|"failed",
  #     hermes_url:, hermes_instance_id:, scoped_token:,
  #     mcp_servers: [...], error: "..." (si failed) }
  def provisioned
    account = Account.find_by(id: params[:account_id])
    return head :not_found if account.nil?

    handoff = JabvoxContextForgeHandoff.find_or_create_by!(account_id: account.id)

    case params[:status].to_s
    when 'ready'
      mark_ready!(handoff)
      head :ok
    when 'failed'
      handoff.mark_failed!(params[:error].presence || 'aprovisionamiento fallido')
      head :ok
    else
      head :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error("[HermesCallback] #{e.message}")
    head :unprocessable_entity
  end

  # Lista las conexiones de DB de la cuenta SIN secretos (para que el aprovisionador sepa
  # cuáles existen antes de pedir las credenciales de una).
  def data_sources
    sources = @account.jabvox_analytics_data_sources.map(&:provisioner_summary)
    render json: { account_id: @account.id, data_sources: sources }
  end

  # Entrega las credenciales COMPLETAS de UNA conexión de DB de la cuenta. Solo el
  # aprovisionador. Se audita cada acceso (sin registrar la contraseña).
  def credentials
    source = @account.jabvox_analytics_data_sources.find_by(id: params[:id])
    return head :not_found if source.nil?

    audit_credentials_access(source)
    render json: source.provisioner_credentials
  end

  private

  # Solo cuentas ligadas a un aprovisionador activo pueden exponer sus data sources.
  def require_linked_account!
    @account = Account.find_by(id: params[:account_id])
    return head :not_found if @account.nil?
    return if JabvoxHermesProvisionerLink.active_for?(@account.id)

    Rails.logger.warn("[HermesCredentials] cuenta #{@account.id} no ligada a aprovisionador")
    head :forbidden
  end

  # Deja rastro del acceso a credenciales (nunca la contraseña).
  def audit_credentials_access(source)
    Rails.logger.info(
      "[HermesCredentials] aprovisionador accedió a data_source=#{source.id} " \
      "cuenta=#{@account.id} engine=#{source.engine_jabvox} db=#{source.database_jabvox}"
    )
  end

  # Marca el handoff operativo en modo "solo Hermes por cuenta": guarda URL + token del
  # Hermes de esa cuenta. El scoped_token se cifra en reposo (Active Record Encryption).
  def mark_ready!(handoff)
    handoff.mark_ready!(
      hermes_url: params[:hermes_url].to_s,
      hermes_instance_id: params[:hermes_instance_id].presence,
      scoped_token: params[:scoped_token].to_s,
      mcp_servers: sanitized_mcps
    )
  end

  # Normaliza la lista de MCPs a [{ 'kind' => ..., 'ok' => true }] (lo que espera el Authorizer).
  def sanitized_mcps
    Array(params[:mcp_servers]).map do |m|
      kind = m.is_a?(ActionController::Parameters) || m.is_a?(Hash) ? m['kind'] || m[:kind] : m
      { 'kind' => kind.to_s, 'ok' => true }
    end
  end

  # DOBLE validación del aprovisionador: token de servicio + usuario de servicio + secreto.
  # Los tres deben coincidir con el aprovisionador único conectado (JabvoxHermesProvisioner).
  # Fallback: si aún no hay usuario de servicio configurado, acepta el ENV compartido (para
  # no romper despliegues previos), pero lo advierte en logs.
  def authenticate_provisioner!
    provisioner = JabvoxHermesProvisioner.instance
    token = request.headers['X-Hermes-Provisioner-Token'].to_s
    service_user_id = request.headers['X-Hermes-Service-User'].to_s
    secret = request.headers['X-Hermes-Service-Secret'].to_s

    return if provisioner.valid_callback?(token: token, service_user_id: service_user_id, secret: secret)
    return if legacy_env_ok?(token)

    Rails.logger.warn('[HermesCallback] doble validación de aprovisionador fallida')
    head :unauthorized
  end

  # Compatibilidad: si el provisioner aún no tiene service_user/secreto, se acepta el token
  # contra el ENV HERMES_PROVISIONER_CALLBACK_SECRET (transición). Una vez configurada la
  # doble validación, este camino deja de aplicar.
  def legacy_env_ok?(token)
    provisioner = JabvoxHermesProvisioner.instance
    return false if provisioner.service_user_id_value.present?

    expected = ENV['HERMES_PROVISIONER_CALLBACK_SECRET'].to_s
    expected.present? && ActiveSupport::SecurityUtils.secure_compare(token, expected)
  end
end
