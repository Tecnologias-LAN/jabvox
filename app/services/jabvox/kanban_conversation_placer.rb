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

    # Un embudo recoge la conversación por CUALQUIERA de sus cuatro orígenes: bandeja,
    # campaña, afiliado o etapa del contacto. Cada uno resuelve por su lado y se unen los ids.
    def funnels_for_conversation
      contact = @conversation.contact
      funnel_ids = funnels_by_inbox +
                   funnels_by_campaign(contact) +
                   funnels_by_affiliate(contact) +
                   funnels_by_lifecycle(contact)
      funnel_ids = funnel_ids.uniq
      return [] if funnel_ids.empty?

      JabvoxKanbanFunnel.where(id: funnel_ids).includes(:jabvox_kanban_stages)
    end

    def active_funnels
      JabvoxKanbanFunnel.where(account_id: @conversation.account_id, active_jabvox: true)
    end

    def funnels_by_inbox
      active_funnels
        .joins(:jabvox_kanban_funnel_inboxes)
        .where(jabvox_kanban_funnel_inboxes: { inbox_id: @conversation.inbox_id })
        .pluck(:id)
    end

    # Campaña y afiliado viven ya en el propio contacto (antes había que pasar por el lead):
    # una consulta menos y sin depender de que exista la fila de lead.
    def funnels_by_campaign(contact)
      return [] if contact&.jabvox_campaign_id.blank?

      active_funnels
        .joins(:jabvox_kanban_funnel_campaigns)
        .where(jabvox_kanban_funnel_campaigns: { jabvox_campaign_id: contact.jabvox_campaign_id })
        .pluck(:id)
    end

    def funnels_by_affiliate(contact)
      return [] if contact&.jabvox_affiliate_id.blank?

      active_funnels
        .joins(:jabvox_kanban_funnel_affiliates)
        .where(jabvox_kanban_funnel_affiliates: { jabvox_affiliate_id: contact.jabvox_affiliate_id })
        .pluck(:id)
    end

    # Etapa del ciclo de vida: sustituye a la distinción "es lead / no es lead" y permite
    # embudos como "reactivación de inactivos" sin depender de bandeja ni campaña.
    def funnels_by_lifecycle(contact)
      return [] if contact.nil?

      active_funnels
        .where('lifecycle_stages_jabvox @> ARRAY[?]::varchar[]', contact.lifecycle_stage)
        .pluck(:id)
    end

    def already_placed?(funnel)
      JabvoxKanbanConversationStage.exists?(
        conversation_id: @conversation.id,
        jabvox_kanban_funnel_id: funnel.id
      )
    end
  end
end
