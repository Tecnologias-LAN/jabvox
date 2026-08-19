# frozen_string_literal: true

# Consumer del Chat IA de la cuenta: expone al frontend el estado del Hermes/ContextForge
# de ESTA cuenta, sincroniza modelos (bidireccional) y lista las tools/MCPs visibles con
# el scoped token de la cuenta.
#
# AISLAMIENTO: usa SOLO el handoff de Current.account; el scoped token tiene alcance
# únicamente al virtual server de esta cuenta, así que list_tools nunca puede ver MCPs de
# otra. El token jamás se envía al frontend.
#
#   GET  .../jabvox/ai_chat_hermes             → estado (sin token) + nº de modelos
#   POST .../jabvox/ai_chat_hermes/sync_models → sync bidireccional de modelos
#   GET  .../jabvox/ai_chat_hermes/tools        → tools/MCPs de la cuenta (aislamiento)
class Api::V1::Accounts::Jabvox::AiChatHermesController < Api::V1::Accounts::Jabvox::BaseController
  include JabvoxPermissions

  jabvox_feature 'jabvox_ai_chat'
  before_action :set_handoff

  def show
    render json: {
      handoff: @handoff&.safe_summary || { status: 'pending', has_token: false, mcp_servers: [] },
      models_count: Current.account.jabvox_ai_chat_models.count,
      hermes_models_count: Current.account.jabvox_ai_chat_models.where(source_jabvox: 'hermes').count
    }
  end

  # Conecta un Hermes YA existente a esta cuenta (base_url + virtual server + token).
  def connect
    return unless jabvox_authorize!('jabvox_ai_chat_manage')

    result = ContextForge::ConnectExistingService.new(
      Current.account,
      base_url: params[:contextforge_base_url],
      virtual_server_id: params[:virtual_server_id],
      scoped_token: params[:scoped_token],
      team_id: params[:team_id],
      hermes_instance_id: params[:hermes_instance_id]
    ).call # attrs va como hash de kwargs -> attrs = {...}

    if result.success?
      render json: result.handoff.safe_summary
    else
      render json: { error: result.error }, status: :unprocessable_entity
    end
  end

  # Sync bidireccional. Escritura → exige permiso de gestión del ai-chat.
  def sync_models
    return unless jabvox_authorize!('jabvox_ai_chat_manage')

    result = ContextForge::ModelSyncService.new(Current.account).call
    if result.success?
      render json: { ok: true, pushed: result.pushed, pulled: result.pulled,
                     models_count: Current.account.jabvox_ai_chat_models.count }
    else
      render json: { ok: false, error: result.error }, status: :unprocessable_entity
    end
  end

  # Lista las tools/MCPs que el Consumer de la cuenta puede usar (con SU scoped token).
  def tools
    return render(json: { error: 'cuenta no aprovisionada' }, status: :unprocessable_entity) unless @handoff&.operational?

    result = ContextForge::Service.new.list_tools(@handoff.scoped_token,
                                                  base_url: @handoff.contextforge_base_url)
    if result.success?
      render json: { tools: result.data }
    else
      render json: { error: result.error }, status: :bad_gateway
    end
  end

  private

  def set_handoff
    @handoff = Current.account.jabvox_context_forge_handoff
  end
end
