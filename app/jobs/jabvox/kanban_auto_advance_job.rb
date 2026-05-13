class Jabvox::KanbanAutoAdvanceJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Jabvox::KanbanAutoAdvanceService.new.perform
    Jabvox::KanbanStageTimeAutomationsService.new.perform
  end
end
