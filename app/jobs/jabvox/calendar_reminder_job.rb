class Jabvox::CalendarReminderJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Jabvox::CalendarReminderService.new.perform
  end
end
