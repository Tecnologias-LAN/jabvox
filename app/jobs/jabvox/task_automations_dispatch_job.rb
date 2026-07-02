# Scheduled (cron) entrypoint for recurring per-task automations. Runs hourly and dispatches
# every automation whose next_run_at has passed.
class Jabvox::TaskAutomationsDispatchJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Jabvox::TaskAutomationsDispatchService.new.perform
  end
end
