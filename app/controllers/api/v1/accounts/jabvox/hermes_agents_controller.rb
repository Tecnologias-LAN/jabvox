# frozen_string_literal: true

# Agentes de la cuenta (uno por usuario). Cada agente Jabvox se liga a uno o varios agentes
# de Hermes (JabvoxHermesConnection, N:N). El admin (jabvox_ai_chat_manage) crea/edita agentes
# y elige qué agentes Hermes puede usar cada uno. NO se gestionan permisos aquí.
#
#   GET    .../jabvox/hermes_agents        → lista (con sus agentes Hermes ligados)
#   POST   .../jabvox/hermes_agents        → crear (user_id + nombre + connection_ids)
#   PATCH  .../jabvox/hermes_agents/:id     → editar (nombre + connection_ids)
#   DELETE .../jabvox/hermes_agents/:id     → eliminar (no el por-defecto)
class Api::V1::Accounts::Jabvox::HermesAgentsController < Api::V1::Accounts::Jabvox::BaseController
  include JabvoxPermissions

  jabvox_feature 'jabvox_ai_chat'
  before_action -> { jabvox_authorize!('jabvox_ai_chat_manage') }
  before_action :set_agent, only: %i[update destroy]

  def index
    agents = JabvoxHermesAgent.where(account_id: Current.account.id)
                              .includes(:hermes_connections, :user).order(:name_jabvox)
    render json: agents.map { |a| serialize(a) }
  end

  def create
    user_id = params[:user_id].to_i
    return render(json: { error: 'El usuario no pertenece a la cuenta' }, status: :not_found) unless user_in_account?(user_id)

    agent = JabvoxHermesAgent.new(
      account_id: Current.account.id, user_id: user_id,
      name_jabvox: params[:name], description_jabvox: params[:description], status_jabvox: 'active'
    )
    if agent.save
      sync_connections(agent, params[:connection_ids])
      # Los permisos de Hermes del usuario se derivan de su rol en la cuenta.
      JabvoxHermesUserPermission.sync_from_role!(Current.account.id, user_id)
      render json: serialize(agent), status: :created
    else
      render json: { errors: agent.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    @agent.assign_attributes(agent_edit_params)
    if @agent.save
      sync_connections(@agent, params[:connection_ids]) unless params[:connection_ids].nil?
      render json: serialize(@agent)
    else
      render json: { errors: @agent.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    return render(json: { error: 'No se puede eliminar el agente por defecto' }, status: :unprocessable_entity) if @agent.is_default_jabvox

    @agent.destroy
    head :no_content
  end

  private

  def set_agent
    @agent = JabvoxHermesAgent.where(account_id: Current.account.id).find(params[:id])
  end

  # Solo actualiza las claves que el request INCLUYÓ (no descarta por blank con
  # compact_blank, que impedía vaciar la descripción). name_jabvox no puede quedar en
  # blanco: si viene incluido pero vacío, se ignora para no romper la validación de
  # presencia; el resto (description, status) sí admite valores vacíos.
  def agent_edit_params
    permitted = params.permit(:name_jabvox, :description_jabvox, :status_jabvox).to_h
    permitted.delete('name_jabvox') if permitted.key?('name_jabvox') && permitted['name_jabvox'].blank?
    permitted
  end

  def user_in_account?(user_id)
    Current.account.account_users.exists?(user_id: user_id)
  end

  # Liga el agente Jabvox a las conexiones Hermes indicadas (N:N). Solo conexiones de la cuenta.
  def sync_connections(agent, ids)
    conns = Current.account.jabvox_hermes_connections.where(id: Array(ids))
    agent.hermes_connections = conns
  end

  def serialize(agent)
    {
      id: agent.id, user_id: agent.user_id, name: agent.name_jabvox,
      user_name: agent.user&.name, user_email: agent.user&.email,
      description: agent.description_jabvox,
      is_default: agent.is_default_jabvox, status: agent.status_jabvox,
      hermes_connections: agent.hermes_connections.map { |c| { id: c.id, name: c.name_jabvox } },
      connection_ids: agent.hermes_connections.map(&:id)
    }
  end
end
