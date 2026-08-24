# frozen_string_literal: true

# Agentes del Hermes de la cuenta. El admin de la cuenta (jabvox_ai_chat_manage) crea/edita
# agentes, cada uno ligado 1:1 a un usuario de la cuenta y con sus permisos granulares. Los
# permisos del agente SON los del usuario ligado (una sola fuente de verdad).
#
#   GET    .../jabvox/hermes_agents        → lista
#   POST   .../jabvox/hermes_agents        → crear (user_id + nombre + permisos)
#   PATCH  .../jabvox/hermes_agents/:id     → editar (nombre/prompt/estado + permisos)
#   DELETE .../jabvox/hermes_agents/:id     → eliminar (no el por-defecto)
class Api::V1::Accounts::Jabvox::HermesAgentsController < Api::V1::Accounts::Jabvox::BaseController
  include JabvoxPermissions

  jabvox_feature 'jabvox_ai_chat'
  before_action -> { jabvox_authorize!('jabvox_ai_chat_manage') }
  before_action :set_agent, only: %i[update destroy]

  def index
    agents = JabvoxHermesAgent.where(account_id: Current.account.id).order(:name_jabvox)
    render json: agents.map { |a| serialize(a) }
  end

  def create
    user_id = params[:user_id].to_i
    return render(json: { error: 'El usuario no pertenece a la cuenta' }, status: :not_found) unless user_in_account?(user_id)

    agent = JabvoxHermesAgent.new(
      account_id: Current.account.id, user_id: user_id,
      name_jabvox: params[:name], description_jabvox: params[:description],
      system_prompt_jabvox: params[:system_prompt], status_jabvox: 'active'
    )
    if agent.save
      apply_permissions(user_id, params[:permissions])
      render json: serialize(agent), status: :created
    else
      render json: { errors: agent.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    @agent.assign_attributes(agent_edit_params)
    if @agent.save
      apply_permissions(@agent.user_id, params[:permissions]) unless params[:permissions].nil?
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

  def agent_edit_params
    params.permit(:name_jabvox, :description_jabvox, :system_prompt_jabvox, :status_jabvox)
          .to_h.compact_blank
  end

  def user_in_account?(user_id)
    Current.account.account_users.exists?(user_id: user_id)
  end

  # Fija los permisos del usuario ligado (= permisos del agente). Solo del catálogo.
  def apply_permissions(user_id, raw)
    permissions = Array(raw).map(&:to_s) & JabvoxHermesUserPermission::PERMISSIONS
    record = JabvoxHermesUserPermission.find_or_initialize_by(account_id: Current.account.id, user_id: user_id)
    record.permissions_jabvox = permissions
    record.save!
  end

  def serialize(agent)
    {
      id: agent.id, user_id: agent.user_id, name: agent.name_jabvox,
      description: agent.description_jabvox, system_prompt: agent.system_prompt_jabvox,
      is_default: agent.is_default_jabvox, status: agent.status_jabvox,
      permissions: agent.permissions
    }
  end
end
