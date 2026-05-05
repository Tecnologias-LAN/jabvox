module Jabvox
  class KanbanConversationPlacer
    def initialize(conversation)
      @conversation = conversation
    end

    def perform
      return unless feature_enabled?

      funnels_for_conversation.each do |funnel|
        next if already_placed?(funnel)
        next unless (first_stage = funnel.first_stage)

        JabvoxKanbanConversationStage.create!(
          conversation_id: @conversation.id,
          jabvox_kanban_funnel_id: funnel.id,
          jabvox_kanban_stage_id: first_stage.id,
          account_id: @conversation.account_id
        )
      end
    end

    private

    def feature_enabled?
      @conversation.account.jabvox_kanban_enabled_jabvox?
    end

    def funnels_for_conversation
      funnel_ids = Set.new

      # Match by inbox
      JabvoxKanbanFunnel
        .joins(:jabvox_kanban_funnel_inboxes)
        .where(account_id: @conversation.account_id, active_jabvox: true,
               jabvox_kanban_funnel_inboxes: { inbox_id: @conversation.inbox_id })
        .pluck(:id).each { |id| funnel_ids << id }

      # Match by campaign / affiliate via lead
      lead = JabvoxLead.find_by(account_id: @conversation.account_id, contact_id: @conversation.contact_id)
      if lead
        if lead.jabvox_campaign_id
          JabvoxKanbanFunnel
            .joins(:jabvox_kanban_funnel_campaigns)
            .where(account_id: @conversation.account_id, active_jabvox: true,
                   jabvox_kanban_funnel_campaigns: { jabvox_campaign_id: lead.jabvox_campaign_id })
            .pluck(:id).each { |id| funnel_ids << id }
        end

        if lead.jabvox_affiliate_id
          JabvoxKanbanFunnel
            .joins(:jabvox_kanban_funnel_affiliates)
            .where(account_id: @conversation.account_id, active_jabvox: true,
                   jabvox_kanban_funnel_affiliates: { jabvox_affiliate_id: lead.jabvox_affiliate_id })
            .pluck(:id).each { |id| funnel_ids << id }
        end
      end

      return [] if funnel_ids.empty?

      JabvoxKanbanFunnel.where(id: funnel_ids.to_a).includes(:jabvox_kanban_stages)
    end

    def already_placed?(funnel)
      JabvoxKanbanConversationStage.exists?(
        conversation_id: @conversation.id,
        jabvox_kanban_funnel_id: funnel.id
      )
    end
  end
end
