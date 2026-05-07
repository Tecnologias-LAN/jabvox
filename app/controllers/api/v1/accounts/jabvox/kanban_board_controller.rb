class Api::V1::Accounts::Jabvox::KanbanBoardController < Api::V1::Accounts::Jabvox::BaseController
  before_action :fetch_funnel
  before_action :check_authorization

  def show
    auto_place_unplaced

    stages = @funnel.jabvox_kanban_stages.ordered.includes(
      jabvox_kanban_conversation_stages: {
        conversation: [:contact, :assignee, :inbox, :labels],
        jabvox_lead: { contact: [] }
      }
    )

    @board = {
      funnel: @funnel,
      stages: stages.map do |stage|
        entries = stage.jabvox_kanban_conversation_stages
        {
          stage: stage,
          conversations: entries.filter_map(&:conversation),
          lead_cards: entries.select { |e| e.jabvox_lead_id.present? && e.conversation_id.nil? }
                             .map { |e| build_lead_card(e) }
        }
      end
    }
  end

  private

  def build_lead_card(entry)
    lead = entry.jabvox_lead
    contact = lead.contact
    {
      lead_stage_id: entry.id,
      lead_id: lead.id,
      lead_number: lead.lead_number,
      created_at: lead.created_at,
      contact: {
        id: contact.id,
        name: jabvox_mask('name', contact.name),
        email: jabvox_mask('email', contact.email),
        phone_number: jabvox_mask('phone', contact.phone_number),
        avatar_url: contact.avatar_url
      }
    }
  end

  def auto_place_unplaced
    first_stage = @funnel.first_stage
    return unless first_stage

    place_unplaced_conversations(first_stage)
    place_unplaced_leads(first_stage)
  end

  def place_unplaced_conversations(first_stage)
    placed_ids = JabvoxKanbanConversationStage
                 .where(jabvox_kanban_funnel_id: @funnel.id)
                 .where.not(conversation_id: nil)
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

  def place_unplaced_leads(first_stage)
    placed_lead_ids = JabvoxKanbanConversationStage
                      .where(jabvox_kanban_funnel_id: @funnel.id)
                      .where.not(jabvox_lead_id: nil)
                      .pluck(:jabvox_lead_id)

    contact_ids_with_open_conv = Current.account.conversations
                                         .where(status: :open)
                                         .pluck(:contact_id).to_set

    unplaced = unplaced_lead_ids(placed_lead_ids, contact_ids_with_open_conv)
    return if unplaced.empty?

    now = Time.current
    rows = unplaced.map do |lid|
      {
        jabvox_lead_id: lid,
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

  def unplaced_lead_ids(placed_lead_ids, contact_ids_with_open_conv)
    ids = Set.new

    campaign_ids = @funnel.jabvox_kanban_funnel_campaigns.pluck(:jabvox_campaign_id)
    if campaign_ids.any?
      JabvoxLead.where(account_id: Current.account.id, jabvox_campaign_id: campaign_ids)
                .where.not(id: placed_lead_ids)
                .each { |l| ids << l.id unless contact_ids_with_open_conv.include?(l.contact_id) }
    end

    affiliate_ids = @funnel.jabvox_kanban_funnel_affiliates.pluck(:jabvox_affiliate_id)
    if affiliate_ids.any?
      JabvoxLead.where(account_id: Current.account.id, jabvox_affiliate_id: affiliate_ids)
                .where.not(id: placed_lead_ids)
                .each { |l| ids << l.id unless contact_ids_with_open_conv.include?(l.contact_id) }
    end

    if @funnel.include_own_leads_jabvox?
      JabvoxLead.where(account_id: Current.account.id, jabvox_affiliate_id: nil)
                .where.not(id: placed_lead_ids)
                .each { |l| ids << l.id unless contact_ids_with_open_conv.include?(l.contact_id) }
    end

    ids.to_a
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

    if @funnel.include_own_leads_jabvox?
      contact_ids = JabvoxLead.where(account_id: Current.account.id, jabvox_affiliate_id: nil).pluck(:contact_id)
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
