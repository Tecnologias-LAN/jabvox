# Scheduled batch: finds every active per-task automation whose next_run_at has passed and
# dispatches it. Only processes automations for accounts with the Tasks module enabled. One
# failing automation is isolated so the rest of the batch still runs.
class Jabvox::TaskAutomationsDispatchService
  def perform(now = Time.current)
    JabvoxTaskAutomation
      .due(now)
      .includes(:account, task: %i[board stage assignees jabvox_lead])
      .find_each { |automation| process(automation) }
  end

  private

  def process(automation)
    return unless automation.account.feature_enabled?('jabvox_tasks')

    Jabvox::TaskAutomationDispatchService.new(automation).perform
  rescue StandardError => e
    Rails.logger.error("[TaskAutomationsDispatch] automation=#{automation.id} error=#{e.message}")
  end
end
