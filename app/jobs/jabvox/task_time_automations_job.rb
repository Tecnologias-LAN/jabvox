# Scheduled (cron) entrypoint for time-based task automations.
class Jabvox::TaskTimeAutomationsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Jabvox::TaskTimeAutomationsService.new.perform
  end
end
