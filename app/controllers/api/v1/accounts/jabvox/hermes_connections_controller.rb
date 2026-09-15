# frozen_string_literal: true

# Conexiones a los agentes del Hermes de la cuenta (varios agentes, mismo host:puerto).
# El admin de la cuenta agrega/edita/prueba cada agente Hermes; el token nunca se devuelve.
#
#   GET    .../jabvox/hermes_connections            → lista (con estado, sin token)
#   POST   .../jabvox/hermes_connections            → crea { name, hermes_agent_name, base_url, token }
#   PATCH  .../jabvox/hermes_connections/:id         → edita
#   DELETE .../jabvox/hermes_connections/:id         → elimina
#   POST   .../jabvox/hermes_connections/:id/verify  → prueba la conexión (health)
class Api::V1::Accounts::Jabvox::HermesConnectionsController < Api::V1::Accounts::Jabvox::BaseController
  include JabvoxPermissions

  jabvox_feature 'jabvox_ai_chat'
  before_action -> { jabvox_authorize_write!('jabvox_ai_chat_manage') },
                except: %i[index mine model_options jobs]
  before_action :set_connection,
                only: %i[update destroy verify model_options jobs create_job pause_job
                         resume_job run_job delete_job]

  def index
    render json: Current.account.jabvox_hermes_connections.order(:name_jabvox).map(&:safe_summary)
  end

  # Conexiones de agentes Hermes que puede usar el USUARIO actual en el Chat IA: las ligadas a
  # su agente Jabvox (N:N). Si no tiene agente ligado, no ve ninguna (no puede chatear con Hermes).
  def mine
    agent = Current.account.jabvox_hermes_agents.find_by(user_id: current_user.id)
    conns = agent ? agent.hermes_connections.order(:name_jabvox) : []
    render json: conns.map(&:safe_summary)
  end

  def create
    conn = Current.account.jabvox_hermes_connections.new(connection_params)
    if conn.save
      render json: conn.safe_summary, status: :created
    else
      render json: { errors: conn.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    # token en blanco = conservar el actual (no sobreescribir con vacío)
    attrs = connection_params
    attrs.delete(:token_jabvox) if attrs[:token_jabvox].blank?
    if @connection.update(attrs)
      render json: @connection.safe_summary
    else
      render json: { errors: @connection.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @connection.destroy
    head :no_content
  end

  # Prueba la conexión al agente Hermes (health por el prefijo) y guarda el estado.
  def verify
    res = client.health
    @connection.mark_status!(success: res.success?, error: res.error)
    render json: @connection.safe_summary
  end

  # Modelos que ofrece ESTE agente (GET .../p/<agente>/api/model/options).
  def model_options
    res = client.model_options
    respond_data(res)
  end

  # Cron / tareas programadas de ESTE agente.
  def jobs
    respond_data(client.list_jobs)
  end

  def create_job
    respond_data(client.create_job(job_params))
  end

  def pause_job
    respond_data(client.pause_job(params[:job_id]))
  end

  def resume_job
    respond_data(client.resume_job(params[:job_id]))
  end

  def run_job
    respond_data(client.run_job(params[:job_id]))
  end

  def delete_job
    respond_data(client.delete_job(params[:job_id]))
  end

  private

  def set_connection
    @connection = Current.account.jabvox_hermes_connections.find(params[:id])
  end

  def client
    @client ||= Jabvox::Hermes::SessionsClient.new(
      base_url: @connection.base_url_jabvox, token: @connection.token_jabvox,
      model: @connection.hermes_agent_name_jabvox
    )
  end

  def job_params
    params.permit(:name, :schedule, :prompt, :deliver, :repeat, skills: []).to_h
  end

  def respond_data(res)
    if res.success?
      render json: (res.respond_to?(:data) ? res.data : {})
    else
      render json: { error: res.error }, status: :bad_gateway
    end
  end

  def connection_params
    permitted = params.permit(:name_jabvox, :hermes_agent_name_jabvox, :base_url_jabvox, :token_jabvox,
                              allowed_ips_jabvox: [])
    return permitted unless params.key?(:allowed_ips_jabvox)

    permitted.merge(allowed_ips_jabvox: normalized_allowed_ips)
  end

  # La allowlist llega como array (JSON) o como texto separado por comas desde un input
  # simple. Se normaliza a array sin vacíos; el modelo valida que cada entrada sea una IP o
  # un CIDR real.
  def normalized_allowed_ips
    raw = params[:allowed_ips_jabvox]
    list = raw.is_a?(Array) ? raw : raw.to_s.split(',')
    list.map { |entry| entry.to_s.strip }.reject(&:blank?)
  end
end
