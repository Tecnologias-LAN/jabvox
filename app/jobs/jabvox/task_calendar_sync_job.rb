# Syncs a task's due date(s) into the real calendar off the request cycle.
class Jabvox::TaskCalendarSyncJob < ApplicationJob
  queue_as :default

  def perform(task_id)
    task = JabvoxTask.find_by(id: task_id)
    return unless task
    return unless task.account.feature_enabled?('jabvox_tasks')

    Jabvox::TaskCalendarSyncService.new(task).sync!
  end
end
