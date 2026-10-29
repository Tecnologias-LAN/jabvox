# frozen_string_literal: true

# jabvox.kanban.list — LECTURA de tarjetas de un embudo Kanban. Dos operaciones:
# `by_funnel` (todas las columnas del embudo) y `by_stage` (una columna concreta).
# Cada tarjeta es una fila de `jabvox_kanban_conversation_stages`: puede venir de
# una CONVERSACIÓN (y su contacto) o de un CONTACTO sin conversación (lead card).
#
# NO auto-coloca tarjetas (eso lo hace el tablero al abrirse): un nodo de lectura
# no debe tener efectos secundarios, solo devuelve lo que YA está colocado.
class Jabvox::Flows::Nodes::Jabvox::KanbanListNode < Jabvox::Flows::Nodes::Jabvox::KanbanBase
  type 'jabvox.kanban.list'
  label 'Obtener Leads de Kanban'
  items_path 'cards'

  SAFETY_LIMIT = 500
  DEFAULT_LIMIT = 100

  def perform
    funnel = find_funnel!(param(:funnelId))
    stage = stage_filter(funnel)
    scope = filtered_scope(funnel, stage)
    total = scope.count
    rows = scope.ordered.limit(limit).offset(offset).to_a

    base_output(funnel, stage, total, rows).merge('cards' => rows.map { |row| card_view(row, funnel) })
  end

  private

  def base_output(funnel, stage, total, rows)
    { 'operation' => stage ? 'by_stage' : 'by_funnel',
      'funnel_id' => funnel.id, 'funnel_name' => funnel.name_jabvox,
      'stage_id' => stage&.id, 'stage_name' => stage&.name_jabvox,
      'count' => rows.length, 'total' => total, 'page' => page, 'per_page' => limit,
      'hasMore' => (offset + rows.length) < total }
  end

  # En `by_stage` la etapa es obligatoria; en `by_funnel` se ignora aunque venga.
  def stage_filter(funnel)
    operation = first_filled(param(:operation), 'by_funnel')
    return nil unless operation == 'by_stage'

    raw = first_filled(param(:stageId))
    fail_with!('La operación "una columna" requiere elegir la etapa del embudo.') if raw.blank?

    find_stage_in_funnel!(raw, funnel)
  end

  # Precarga lo que `card_view` necesita (conversación con su contacto y agente, o
  # el contacto directo con su empresa) para no disparar una consulta por tarjeta.
  def filtered_scope(funnel, stage)
    scope = JabvoxKanbanConversationStage
            .where(account_id: account.id, jabvox_kanban_funnel_id: funnel.id)
            .includes(:jabvox_kanban_stage,
                      conversation: [:assignee, { contact: :company }],
                      contact: :company)
    scope = scope.where(jabvox_kanban_stage_id: stage.id) if stage
    scope = apply_assignee(scope)
    scope = apply_labels(scope)
    apply_created_range(scope)
  end

  # Agente asignado: igual que el tablero, sale de la conversación o, si la tarjeta
  # es un contacto sin conversación, del propio contacto. Se expresa como una sola
  # condición OR sobre subconsultas para no chocar con el `.or` de scopes dispares.
  def apply_assignee(scope)
    return scope if blank_param?(param(:assigneeId))

    agent_id = param(:assigneeId)
    conv_ids = account.conversations.where(assignee_id: agent_id).select(:id)
    contact_ids = account.contacts.where(assignee_id: agent_id).select(:id)
    scope.where(
      'jabvox_kanban_conversation_stages.conversation_id IN (:conv) ' \
      'OR jabvox_kanban_conversation_stages.contact_id IN (:contacts)',
      conv: conv_ids, contacts: contact_ids
    )
  end

  # Por etiqueta: la etiqueta vive en el CONTACTO (reusa Labelable como el resto).
  def apply_labels(scope)
    label = first_filled(param(:label)).downcase
    return scope if label.blank?

    contact_ids = account.contacts.tagged_with(label).select(:id)
    scope.where(contact_id: contact_ids)
  end

  def apply_created_range(scope)
    from = parse_time(param(:createdFrom))
    to = parse_time(param(:createdTo))
    scope = scope.where('jabvox_kanban_conversation_stages.created_at >= ?', from) if from
    scope = scope.where('jabvox_kanban_conversation_stages.created_at <= ?', to) if to
    scope
  end

  # Vista de una tarjeta: embudo y etapa actuales, posición, contacto (ficha
  # completa), conversación si la hay, y el agente asignado.
  def card_view(row, funnel)
    stage = row.jabvox_kanban_stage
    contact = row.contact || row.conversation&.contact
    conversation = row.conversation
    { 'id' => row.id, 'position' => row.position_jabvox,
      'funnel_id' => funnel.id, 'funnel_name' => funnel.name_jabvox,
      'stage_id' => stage&.id, 'stage_name' => stage&.name_jabvox,
      'stage_position' => stage&.position_jabvox,
      'lead_id' => contact&.id, 'contact_id' => contact&.id,
      'contact' => contact_view(contact),
      'conversation_id' => conversation&.id,
      'conversation_display_id' => conversation&.display_id,
      'assignee' => user_view(assignee_of(row, contact, conversation)) }
  end

  def assignee_of(_row, contact, conversation)
    conversation&.assignee || contact&.assignee
  end

  def user_view(user)
    return nil if user.nil?

    { 'id' => user.id, 'name' => user.name, 'email' => user.email }
  end

  def parse_time(raw)
    return nil if blank_param?(raw)

    Time.zone.parse(raw.to_s) || fail_with!(bad_range_message(raw))
  rescue ArgumentError, TypeError
    fail_with!(bad_range_message(raw))
  end

  def bad_range_message(raw)
    "No se entiende la fecha \"#{raw}\" del filtro. Usa 2026-08-15 o 2026-08-15 09:00."
  end

  def limit
    @limit ||= int_or(param(:limit), DEFAULT_LIMIT, min: 1, max: SAFETY_LIMIT)
  end

  def page
    @page ||= int_or(param(:page), 1, min: 1)
  end

  def offset
    (page - 1) * limit
  end
end
