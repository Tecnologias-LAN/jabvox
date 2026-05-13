class Jabvox::KanbanStageTimeAutomationsService
  def perform
    process_move_after_hours
    process_move_if_inactive
  end

  private

  def process_move_after_hours
    JabvoxKanbanStageAutomation
      .where(automation_type: 'move_after_hours', active: true)
      .where.not(target_stage_id: nil)
      .where.not(trigger_hours: nil)
      .find_each { |auto| advance_for(auto) }
  end

  def process_move_if_inactive
    JabvoxKanbanStageAutomation
      .where(automation_type: 'move_if_inactive', active: true)
      .where.not(target_stage_id: nil)
      .where.not(trigger_hours: nil)
      .find_each { |auto| move_inactive_for(auto) }
  end

  def advance_for(auto)
    cutoff = auto.trigger_hours.hours.ago
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
    cutoff = auto.trigger_hours.hours.ago
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
    elsif cs.jabvox_lead_id.present?
      cs.jabvox_lead&.contact
    end
  end
end
