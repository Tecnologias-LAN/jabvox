class Api::V1::Accounts::Jabvox::KanbanBoardController < Api::V1::Accounts::Jabvox::BaseController
  before_action :fetch_funnel
  before_action :check_authorization

  def show
    auto_place_unplaced_conversations

    stages = @funnel.jabvox_kanban_stages.ordered.includes(
      jabvox_kanban_conversation_stages: {
        conversation: [:contact, :assignee, :inbox, :labels]
      }
    )

    @board = {
      funnel: @funnel,
      stages: stages.map do |stage|
        {
          stage: stage,
          conversations: stage.jabvox_kanban_conversation_stages
                              .filter_map(&:conversation)
        }
      end
    }
  end

  private

  def auto_place_unplaced_conversations
    first_stage = @funnel.first_stage
    return unless first_stage

    placed_ids = JabvoxKanbanConversationStage
                 .where(jabvox_kanban_funnel_id: @funnel.id)
                 .pluck(:conversation_id)

    unplaced_ids = unplaced_conversation_ids(placed_ids)
    return if unplaced_ids.empty?

    now = Time.current
    rows = unplaced_ids.map do |cid|
      {
        conversation_id: cid,
        jabvox_kanban_funnel_id: @funnel.id,
        jabvox_kanban_stage_id: first_stage.id,
        account_id: Current.account.id,
        created_at: now,
        updated_at: now
      }
    end
    # rubocop:disable Rails/SkipsModelValidations
    JabvoxKanbanConversationStage.insert_all(rows)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def unplaced_conversation_ids(placed_ids)
    base = Current.account.conversations.where(status: :open).where.not(id: placed_ids)
    ids = Set.new

    inbox_ids = @funnel.jabvox_kanban_funnel_inboxes.pluck(:inbox_id)
    ids.merge(base.where(inbox_id: inbox_ids).pluck(:id)) if inbox_ids.any?

    campaign_ids = @funnel.jabvox_kanban_funnel_campaigns.pluck(:jabvox_campaign_id)
    if campaign_ids.any?
      contact_ids = JabvoxLead.where(account_id: Current.account.id, jabvox_campaign_id: campaign_ids).pluck(:contact_id)
      ids.merge(base.where(contact_id: contact_ids).pluck(:id)) if contact_ids.any?
    end

    affiliate_ids = @funnel.jabvox_kanban_funnel_affiliates.pluck(:jabvox_affiliate_id)
    if affiliate_ids.any?
      contact_ids = JabvoxLead.where(account_id: Current.account.id, jabvox_affiliate_id: affiliate_ids).pluck(:contact_id)
      ids.merge(base.where(contact_id: contact_ids).pluck(:id)) if contact_ids.any?
    end

    ids.to_a
  end

  def fetch_funnel
    funnel_id = params[:funnel_id] || params[:kanban_funnel_id]
    @funnel = Current.account.jabvox_kanban_funnels.find(funnel_id)
  end

  def check_authorization
    authorize @funnel, :show?
  end
end
