# frozen_string_literal: true

# Chat Aprovisionamiento de UNA cuenta: el usuario (con permiso) le pide al Hermes
# Provisioner de su cuenta crear/aprovisionar MCPs. Gateado por el módulo
# jabvox_ai_chat_provisioning Y por el permiso de usuario jabvox_ai_chat_provisioning_manage.
#
# AISLAMIENTO: todo ocurre dentro de Current.account; nunca se toca otra cuenta. El
# aprovisionamiento crea/usa SOLO el handoff (team+MCPs+virtual server+token) de esta cuenta.
#
#   GET  .../provisioning_chat_messages          → historial de esta cuenta
#   POST .../provisioning_chat_messages          → { content } → respuesta del Provisioner
#   GET  .../provisioning_chat_messages/status    → estado del handoff (sin token)
#   POST .../provisioning_chat_messages/provision → aprovisionamiento inicial (idempotente)
class Api::V1::Accounts::Jabvox::ProvisioningChatMessagesController < Api::V1::Accounts::Jabvox::BaseController
  include JabvoxPermissions

  jabvox_feature 'jabvox_ai_chat_provisioning'
  # Todas las acciones exigen el permiso de gestión (crear MCPs es una acción sensible).
  before_action -> { jabvox_authorize!('jabvox_ai_chat_provisioning_manage') }

  def index
    msgs = Current.account.jabvox_provisioning_chat_messages.chronological.limit(200)
    render json: msgs.map { |m| serialize(m) }
  end

  def create
    content = params[:content].to_s.strip
    return render(json: { error: 'content requerido' }, status: :unprocessable_entity) if content.blank?

    persist('user', content)
    result = Jabvox::ProvisioningChatService.new(
      account: Current.account, user: Current.user
    ).handle(content)
    assistant = persist('assistant', result[:reply], metadata: result[:metadata] || {})
    render json: serialize(assistant)
  end

  # Estado del aprovisionamiento de la cuenta (nunca expone el token).
  def status
    handoff = Current.account.jabvox_context_forge_handoff
    render json: (handoff&.safe_summary || { status: 'pending', mcp_servers: [], has_token: false })
  end

  # Dispara el aprovisionamiento inicial (crea Hermes + MCPs por defecto + virtual server
  # + scoped token). Idempotente. Corre inline pero acotado por el timeout del service.
  def provision
    result = ContextForge::AccountProvisioner.new(Current.account).call
    handoff = Current.account.jabvox_context_forge_handoff
    if result.success?
      render json: (handoff&.safe_summary || {}).merge(steps: result.steps)
    else
      render json: { error: result.error, status: handoff&.status || 'failed', steps: result.steps },
             status: :unprocessable_entity
    end
  end

  private

  def persist(role, content, metadata: {})
    Current.account.jabvox_provisioning_chat_messages.create!(
      user: Current.user, role: role, content: content, metadata: metadata
    )
  end

  def serialize(msg)
    { id: msg.id, role: msg.role, content: msg.content, metadata: msg.metadata,
      created_at: msg.created_at }
  end
end
