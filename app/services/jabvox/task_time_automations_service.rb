# Scheduled service: advances task cards whose stage has a time-based automation
# (move_after_hours / move_if_inactive). Moving a card updates its stage_id, which fires
# that stage's own automations via the model's after_commit hook.
class Jabvox::TaskTimeAutomationsService
  def perform
    JabvoxTaskStageAutomation
      .active
      .where(automation_type_jabvox: %w[move_after_hours move_if_inactive])
      .where.not(target_stage_id: nil)
      .where.not(trigger_hours_jabvox: nil)
      .find_each { |auto| process(auto) }
  end

  private

  def process(auto)
    cutoff = auto.trigger_hours_jabvox.to_i.hours.ago
    JabvoxTask
      .where(stage_id: auto.stage_id, status_jabvox: 'open')
      .where(updated_at: ..cutoff)
      .find_each do |task|
      task.update!(stage_id: auto.target_stage_id)
    rescue StandardError => e
      Rails.logger.error("[TaskTimeAutomations] auto=#{auto.id} task=#{task.id} error=#{e.message}")
    end
  end
end
