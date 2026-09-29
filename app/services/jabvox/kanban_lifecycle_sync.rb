# frozen_string_literal: true

# Retira las tarjetas de un contacto de los embudos que ya no le corresponden por su etapa
# del ciclo de vida.
#
# Un embudo puede recoger contactos por bandeja, campaña, afiliado, "propios" o etapa. Solo
# se retira de los que dependen EXCLUSIVAMENTE de la etapa: si el embudo también recoge por
# la bandeja de la conversación o por su campaña, el contacto sigue perteneciendo a él
# aunque cambie de etapa, y sacarlo sería perder una tarjeta que el agente espera ver.
#
# Se llama al cambiar la etapa. La colocación en el embudo nuevo la hace el tablero al
# abrirse (`auto_place_unplaced`), así que aquí solo hay que quitar.
class Jabvox::KanbanLifecycleSync
  def initialize(contact)
    @contact = contact
  end

  # Devuelve cuántas tarjetas se retiraron.
  def perform
    return 0 unless feature_enabled?

    stale_entries.destroy_all.size
  end

  private

  def feature_enabled?
    @contact.account&.jabvox_kanban_enabled_jabvox?
  end

  # Tarjetas del contacto en embudos cuya única razón para tenerlo era una etapa que ya
  # no es la suya.
  def stale_entries
    JabvoxKanbanConversationStage
      .where(account_id: @contact.account_id, contact_id: @contact.id)
      .where(jabvox_kanban_funnel_id: stale_funnel_ids)
  end

  def stale_funnel_ids
    candidates = JabvoxKanbanFunnel
                 .where(account_id: @contact.account_id)
                 .where.not(lifecycle_stages_jabvox: [])

    candidates.reject { |funnel| keeps_contact?(funnel) }.map(&:id)
  end

  # ¿El embudo conserva al contacto por algún motivo distinto de la etapa?
  def keeps_contact?(funnel)
    return true if Array(funnel.lifecycle_stages_jabvox).include?(@contact.lifecycle_stage)
    return true if funnel.include_own_contacts_jabvox? && @contact.jabvox_affiliate_id.nil?
    return true if matches_campaign?(funnel)
    return true if matches_affiliate?(funnel)

    matches_inbox?(funnel)
  end

  def matches_campaign?(funnel)
    return false if @contact.jabvox_campaign_id.blank?

    funnel.jabvox_kanban_funnel_campaigns
          .exists?(jabvox_campaign_id: @contact.jabvox_campaign_id)
  end

  def matches_affiliate?(funnel)
    return false if @contact.jabvox_affiliate_id.blank?

    funnel.jabvox_kanban_funnel_affiliates
          .exists?(jabvox_affiliate_id: @contact.jabvox_affiliate_id)
  end

  # La tarjeta puede venir de una conversación en una bandeja que el embudo vigila.
  def matches_inbox?(funnel)
    inbox_ids = funnel.jabvox_kanban_funnel_inboxes.pluck(:inbox_id)
    return false if inbox_ids.empty?

    @contact.conversations.exists?(inbox_id: inbox_ids)
  end
end
