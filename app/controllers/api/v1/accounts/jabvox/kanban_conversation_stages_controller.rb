class Api::V1::Accounts::Jabvox::KanbanConversationStagesController < Api::V1::Accounts::Jabvox::BaseController
  before_action :fetch_funnel
  before_action :check_authorization

  def update
    stage = @funnel.jabvox_kanban_stages.find(params[:stage_id])
    conversation = Current.account.conversations.find(params[:conversation_id])
    return render_forbidden unless can_manage_conversation?(conversation)

    placement = JabvoxKanbanConversationStage.find_or_initialize_by(
      conversation_id: conversation.id,
      jabvox_kanban_funnel_id: @funnel.id
    )

    placement.assign_attributes(
      jabvox_kanban_stage_id: stage.id,
      account_id: Current.account.id,
      moved_by_id: current_user.id
    )
    placement.save!

    render json: { conversation_id: conversation.id, stage_id: stage.id }, status: :ok
  end

  def update_lead
    stage = @funnel.jabvox_kanban_stages.find(params[:stage_id])
    lead = Current.account.jabvox_leads.find(params[:lead_id])
    return render_forbidden unless can_manage_lead?(lead)

    placement = JabvoxKanbanConversationStage.find_or_initialize_by(
      jabvox_lead_id: lead.id,
      jabvox_kanban_funnel_id: @funnel.id
    )

    placement.assign_attributes(
      jabvox_kanban_stage_id: stage.id,
      account_id: Current.account.id,
      moved_by_id: current_user.id
    )
    placement.save!

    render json: { lead_id: lead.id, stage_id: stage.id }, status: :ok
  end

  private

  # Admins can move any card; an agent may only move conversations/leads assigned to them,
  # so an agent can't reach another agent's lead by guessing its id.
  def can_manage_conversation?(conversation)
    return true if Current.account_user&.administrator?

    conversation.assignee_id == current_user.id
  end

  def can_manage_lead?(lead)
    return true if Current.account_user&.administrator?

    lead.assignee_id == current_user.id
  end

  def render_forbidden
    render json: { error: 'No tienes acceso a este registro' }, status: :forbidden
  end

  def fetch_funnel
    funnel_id = params[:funnel_id] || params[:kanban_funnel_id]
    @funnel = Current.account.jabvox_kanban_funnels.find(funnel_id)
  end

  def check_authorization
    authorize JabvoxKanbanConversationStage, :update?
  end
end
