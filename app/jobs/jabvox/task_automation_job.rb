# Runs a task's stage automations off the request cycle (message dispatch + webhook).
class Jabvox::TaskAutomationJob < ApplicationJob
  queue_as :default

  def perform(task_id)
    task = JabvoxTask.find_by(id: task_id)
    return unless task
    return unless task.account.feature_enabled?('jabvox_tasks')

    Jabvox::TaskAutomationExecutorService.new(task).perform
  end
end
