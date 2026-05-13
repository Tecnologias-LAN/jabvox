class Jabvox::KanbanAutoAdvanceService
  def perform
    JabvoxKanbanStage
      .where(auto_advance_enabled: true)
      .where.not(auto_advance_target_stage_id: nil)
      .where.not(auto_advance_hours: nil)
      .find_each { |stage| advance_for_stage(stage) }
  end

  private

  def advance_for_stage(stage)
    cutoff = stage.auto_advance_hours.hours.ago
    JabvoxKanbanConversationStage
      .where(jabvox_kanban_stage_id: stage.id)
      .where('updated_at <= ?', cutoff)
      .find_each do |cs|
        cs.update!(jabvox_kanban_stage_id: stage.auto_advance_target_stage_id)
      rescue StandardError => e
        Rails.logger.error("[KanbanAutoAdvance] cs=#{cs.id} stage=#{stage.id} error=#{e.message}")
      end
  end
end
