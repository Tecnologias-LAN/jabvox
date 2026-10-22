class Api::V1::Accounts::Jabvox::KanbanConversationStagesController < Api::V1::Accounts::Jabvox::BaseController
  jabvox_feature 'jabvox_kanban'
  include JabvoxPermissions

  before_action :fetch_funnel
  before_action :check_authorization
  # Moving cards is a management action. Enforced only for users on a custom role so plain
  # agents keep moving their own cards; admins always pass via jabvox_authorize!.
  before_action -> { jabvox_gate!('jabvox_kanban_manage') }, only: %i[update update_lead reorder]

  def update
    stage = @funnel.jabvox_kanban_stages.find(params[:stage_id])
    conversation = Current.account.conversations.find(params[:conversation_id])
    return render_forbidden unless can_manage_conversation?(conversation)

    placement = place_card!(stage, conversation_id: conversation.id)
    render json: { conversation_id: conversation.id, stage_id: stage.id, position: placement.position_jabvox }, status: :ok
  end

  # `lead_id` en la ruta es hoy el id del CONTACTO: se conserva el nombre del parámetro para
  # no romper al frontend, que ya envía ese valor.
  def update_lead
    stage = @funnel.jabvox_kanban_stages.find(params[:stage_id])
    contact = Current.account.contacts.find(params[:lead_id])
    return render_forbidden unless can_manage_lead?(contact)

    placement = place_card!(stage, contact_id: contact.id)
    render json: { lead_id: contact.id, stage_id: stage.id, position: placement.position_jabvox }, status: :ok
  end

  # Reordena TODAS las tarjetas de una columna (etapa) según la lista de ids recibida.
  # Atómico: recompacta position_jabvox de 0..n en el orden dado. Solo toca tarjetas
  # de esta cuenta/funnel/etapa; ids ajenos o de otra columna se ignoran.
  def reorder
    stage = @funnel.jabvox_kanban_stages.find(params[:stage_id])
    ordered = reorder_items # [{ type:'conversation'|'lead', id: }]

    ActiveRecord::Base.transaction do
      scope = JabvoxKanbanConversationStage.where(account_id: Current.account.id,
                                                  jabvox_kanban_funnel_id: @funnel.id,
                                                  jabvox_kanban_stage_id: stage.id)
      ordered.each_with_index do |item, index|
        row = find_card_in_scope(scope, item)
        next if row.nil?

        row.update_columns(position_jabvox: index, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    render json: { stage_id: stage.id, count: ordered.size }, status: :ok
  end

  private

  # Coloca/mueve una tarjeta en una etapa, respetando una posición de destino opcional.
  # Sin `position`, va al final de la columna (set_default_position). Con `position`,
  # se inserta ahí y se recompacta el resto de la columna destino.
  def place_card!(stage, conversation_id: nil, contact_id: nil)
    key = conversation_id ? { conversation_id: conversation_id } : { contact_id: contact_id }
    target_position = params[:position].present? ? params[:position].to_i : nil

    ActiveRecord::Base.transaction do
      placement = JabvoxKanbanConversationStage.find_or_initialize_by(key.merge(jabvox_kanban_funnel_id: @funnel.id))
      placement.assign_attributes(jabvox_kanban_stage_id: stage.id, account_id: Current.account.id,
                                  moved_by_id: current_user.id)
      placement.position_jabvox = target_position if target_position
      placement.save!
      resequence_stage!(stage.id, placement.id, target_position) if target_position
      placement
    end
  end

  # Deja las posiciones de la columna como 0..n, insertando la tarjeta movida en
  # `target_position` sin huecos ni duplicados.
  def resequence_stage!(stage_id, moved_id, target_position)
    others = JabvoxKanbanConversationStage
             .where(account_id: Current.account.id, jabvox_kanban_funnel_id: @funnel.id, jabvox_kanban_stage_id: stage_id)
             .where.not(id: moved_id).order(:position_jabvox, created_at: :desc).to_a
    ordered_ids = others.map(&:id)
    ordered_ids.insert([target_position, ordered_ids.size].min, moved_id)
    ordered_ids.each_with_index do |id, index|
      JabvoxKanbanConversationStage.where(id: id).update_all(position_jabvox: index) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def reorder_items
    Array(params[:cards]).map do |c|
      c = c.respond_to?(:to_unsafe_h) ? c.to_unsafe_h : c
      if c['conversation_id'].present? || c[:conversation_id].present?
        { type: 'conversation', id: (c['conversation_id'] || c[:conversation_id]).to_i }
      else
        { type: 'lead', id: (c['lead_id'] || c[:lead_id]).to_i }
      end
    end
  end

  def find_card_in_scope(scope, item)
    if item[:type] == 'conversation'
      scope.find_by(conversation_id: item[:id])
    else
      scope.find_by(contact_id: item[:id])
    end
  end

  # Enforce a custom-role permission ONLY for users who actually have a custom role, so
  # standard agents keep their historical flow and admins always pass.
  def jabvox_gate!(key)
    return if Current.account_user&.custom_role.nil?

    jabvox_authorize!(key)
  end

  # Admins (or a custom role that grants the whole board) can move any card; an agent may only
  # move conversations/leads assigned to them, so an agent can't reach another agent's card by
  # guessing its id.
  def can_manage_conversation?(conversation)
    return true if Current.account_user&.administrator?
    return true if jabvox_can?('jabvox_kanban_view_all')

    conversation.assignee_id == current_user.id
  end

  def can_manage_lead?(contact)
    return true if Current.account_user&.administrator?
    return true if jabvox_can?('jabvox_kanban_view_all')

    contact.assignee_id == current_user.id
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
