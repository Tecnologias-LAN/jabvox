class Jabvox::KanbanStageTimeAutomationsService
  def perform
    process_move_after_hours
    process_move_if_inactive
    process_move_if_no_messages('move_if_no_incoming', :incoming)
    process_move_if_no_messages('move_if_no_outgoing', :outgoing)
  end

  private

  def process_move_after_hours
    JabvoxKanbanStageAutomation
      .where(automation_type: 'move_after_hours', active: true)
      .where.not(target_stage_id: nil)
      .find_each { |auto| advance_for(auto) }
  end

  def process_move_if_inactive
    JabvoxKanbanStageAutomation
      .where(automation_type: 'move_if_inactive', active: true)
      .where.not(target_stage_id: nil)
      .find_each { |auto| move_inactive_for(auto) }
  end

  # Mueve las tarjetas cuya conversación lleva el tiempo configurado SIN mensajes en el
  # sentido dado: sin entrantes = el cliente no responde; sin salientes = nadie le ha escrito.
  def process_move_if_no_messages(type, direction)
    JabvoxKanbanStageAutomation
      .where(automation_type: type, active: true)
      .where.not(target_stage_id: nil)
      .find_each { |auto| move_without_messages(auto, direction) }
  end

  def move_without_messages(auto, direction)
    cutoff = auto.trigger_cutoff
    return unless cutoff

    JabvoxKanbanConversationStage
      .where(jabvox_kanban_stage_id: auto.jabvox_kanban_stage_id)
      .find_each do |cs|
        next unless stale_without_messages?(cs, direction, cutoff)

        cs.update!(jabvox_kanban_stage_id: auto.target_stage_id)
      rescue StandardError => e
        Rails.logger.error("[KanbanMoveNoMessages] auto=#{auto.id} cs=#{cs.id} error=#{e.message}")
      end
  end

  # Una tarjeta sin conversación no tiene mensajes que medir, así que nunca se mueve por esta
  # regla: moverla sería tratarla como "sin respuesta" cuando en realidad no hay canal.
  def stale_without_messages?(conversation_stage, direction, cutoff)
    return false if conversation_stage.conversation_id.blank?

    last_at = Message.where(conversation_id: conversation_stage.conversation_id,
                            message_type: direction, private: false)
                     .maximum(:created_at)
    last_at.nil? || last_at <= cutoff
  end

  def advance_for(auto)
    cutoff = auto.trigger_cutoff
    return unless cutoff

    JabvoxKanbanConversationStage
      .where(jabvox_kanban_stage_id: auto.jabvox_kanban_stage_id)
      .where('updated_at <= ?', cutoff)
      .find_each do |cs|
        cs.update!(jabvox_kanban_stage_id: auto.target_stage_id)
      rescue StandardError => e
        Rails.logger.error("[KanbanMoveAfterHours] auto=#{auto.id} cs=#{cs.id} error=#{e.message}")
      end
  end

  def move_inactive_for(auto)
    cutoff = auto.trigger_cutoff
    return unless cutoff

    JabvoxKanbanConversationStage
      .where(jabvox_kanban_stage_id: auto.jabvox_kanban_stage_id)
      .find_each do |cs|
        contact = resolve_contact(cs)
        next unless contact

        last_note_at = Note.where(contact_id: contact.id, account_id: cs.account_id)
                           .maximum(:created_at)
        next if last_note_at && last_note_at > cutoff

        cs.update!(jabvox_kanban_stage_id: auto.target_stage_id)
      rescue StandardError => e
        Rails.logger.error("[KanbanMoveIfInactive] auto=#{auto.id} cs=#{cs.id} error=#{e.message}")
      end
  end

  def resolve_contact(cs)
    if cs.conversation_id.present?
      cs.conversation&.contact
    elsif cs.contact_id.present?
      cs.contact
    end
  end
end
