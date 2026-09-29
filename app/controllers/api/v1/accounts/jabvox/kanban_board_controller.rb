class Api::V1::Accounts::Jabvox::KanbanBoardController < Api::V1::Accounts::Jabvox::BaseController
  jabvox_feature 'jabvox_kanban'
  include JabvoxPermissions

  before_action :fetch_funnel
  before_action :check_authorization

  def show
    auto_place_unplaced

    stages = @funnel.jabvox_kanban_stages.ordered.includes(
      jabvox_kanban_conversation_stages: {
        conversation: [:contact, :assignee, :inbox, :labels],
        contact: []
      }
    )

    @board = {
      funnel: @funnel,
      stages: stages.map do |stage|
        entries = stage.jabvox_kanban_conversation_stages.select { |e| visible_entry?(e) }
        {
          stage: stage,
          conversations: entries.filter_map(&:conversation),
          lead_cards: entries.select { |e| e.contact_id.present? && e.conversation_id.nil? }
                             .map { |e| build_lead_card(e) }
        }
      end
    }
  end

  private

  # Admins see the whole funnel; an agent only sees cards that belong to them — leads
  # assigned to them and conversations assigned to them. Mirrors the per-agent scoping the
  # leads list uses (leads_controller#build_filter_scope), so the board can't leak leads or
  # conversations that weren't assigned to the agent.
  def visible_entry?(entry)
    return true if Current.account_user&.administrator?
    # Custom role that grants the whole board sees every card, like an admin.
    return true if jabvox_can?('jabvox_kanban_view_all')

    if entry.contact_id.present? && entry.conversation_id.nil?
      entry.contact&.assignee_id == current_user.id
    elsif entry.conversation_id.present?
      entry.conversation&.assignee_id == current_user.id
    else
      false
    end
  end

  # Tarjeta de un contacto sin conversación abierta. Conserva las claves `lead_*` que el
  # frontend ya consume; lo que cambia es de dónde salen los datos.
  def build_lead_card(entry)
    contact = entry.contact
    {
      lead_stage_id: entry.id,
      lead_id: contact.id,
      lead_number: nil,
      created_at: contact.created_at,
      contact: {
        id: contact.id,
        name: jabvox_mask('name', contact.name),
        email: jabvox_mask('email', contact.email),
        phone_number: jabvox_mask('phone', contact.phone_number),
        avatar_url: contact.avatar_url,
        lifecycle_stage: contact.lifecycle_stage
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
    placed_contact_ids = JabvoxKanbanConversationStage
                         .where(jabvox_kanban_funnel_id: @funnel.id)
                         .where.not(contact_id: nil)
                         .pluck(:contact_id)

    contact_ids_with_open_conv = Current.account.conversations
                                        .where(status: :open)
                                        .pluck(:contact_id).to_set

    unplaced = unplaced_lead_ids(placed_contact_ids, contact_ids_with_open_conv)
    return if unplaced.empty?

    now = Time.current
    rows = unplaced.map do |cid|
      {
        contact_id: cid,
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

  # Contactos que el embudo debería mostrar y todavía no están colocados. Campaña y afiliado
  # viven ya en el propio contacto, así que no hace falta pasar por la tabla de leads.
  def unplaced_lead_ids(placed_contact_ids, contact_ids_with_open_conv)
    ids = Set.new
    excluded = Set.new(placed_contact_ids) | Set.new(contact_ids_with_open_conv)

    campaign_ids = @funnel.jabvox_kanban_funnel_campaigns.pluck(:jabvox_campaign_id)
    collect_contacts(ids, excluded, jabvox_campaign_id: campaign_ids) if campaign_ids.any?

    affiliate_ids = @funnel.jabvox_kanban_funnel_affiliates.pluck(:jabvox_affiliate_id)
    collect_contacts(ids, excluded, jabvox_affiliate_id: affiliate_ids) if affiliate_ids.any?

    # 'Propios' = los que no vinieron de un afiliado.
    collect_contacts(ids, excluded, jabvox_affiliate_id: nil) if @funnel.include_own_contacts_jabvox?

    stages = funnel_lifecycle_stages
    collect_contacts(ids, excluded, lifecycle_stage_jabvox: stages) if stages.any?

    ids.to_a
  end

  # Añade a `ids` las conversaciones cuyos contactos cumplen las condiciones dadas.
  def merge_by_contact(ids, base, conditions)
    contact_ids = Current.account.contacts.where(conditions).pluck(:id)
    ids.merge(base.where(contact_id: contact_ids).pluck(:id)) if contact_ids.any?
  end

  def collect_contacts(ids, excluded, conditions)
    Current.account.contacts.where(conditions).pluck(:id).each do |id|
      ids << id unless excluded.include?(id)
    end
  end

  def unplaced_conversation_ids(placed_ids)
    base = Current.account.conversations.where(status: :open).where.not(id: placed_ids)
    ids = Set.new

    inbox_ids = @funnel.jabvox_kanban_funnel_inboxes.pluck(:inbox_id)
    ids.merge(base.where(inbox_id: inbox_ids).pluck(:id)) if inbox_ids.any?

    merge_contact_sources(ids, base)

    ids.to_a
  end

  # Fuentes que viven en el propio contacto: se consultan directo, sin pasar por la tabla
  # de leads.
  def merge_contact_sources(ids, base)
    campaign_ids = @funnel.jabvox_kanban_funnel_campaigns.pluck(:jabvox_campaign_id)
    merge_by_contact(ids, base, jabvox_campaign_id: campaign_ids) if campaign_ids.any?

    affiliate_ids = @funnel.jabvox_kanban_funnel_affiliates.pluck(:jabvox_affiliate_id)
    merge_by_contact(ids, base, jabvox_affiliate_id: affiliate_ids) if affiliate_ids.any?

    # 'Propios' = contactos que no vinieron de un afiliado.
    merge_by_contact(ids, base, jabvox_affiliate_id: nil) if @funnel.include_own_contacts_jabvox?

    # Etapa del ciclo de vida del contacto (cliente, prospecto...): un embudo puede
    # existir solo para una etapa, sin bandeja ni campaña ni afiliado configurados.
    stages = funnel_lifecycle_stages
    merge_by_contact(ids, base, lifecycle_stage_jabvox: stages) if stages.any?
  end

  # Solo etapas del catálogo: una fila vieja con un valor que ya no existe no debe
  # arrastrar contactos al tablero.
  def funnel_lifecycle_stages
    Array(@funnel.lifecycle_stages_jabvox) & Jabvox::ContactLifecycle::LIFECYCLE_STAGES
  end

  def fetch_funnel
    funnel_id = params[:funnel_id] || params[:kanban_funnel_id]
    @funnel = Current.account.jabvox_kanban_funnels.find(funnel_id)
  end

  def check_authorization
    authorize @funnel, :show?
  end
end
