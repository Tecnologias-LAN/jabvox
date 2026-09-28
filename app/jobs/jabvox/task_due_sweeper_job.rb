# frozen_string_literal: true

# Recordatorios de tareas que vencen y apartado de las vencidas. Ver
# Jabvox::TaskDueSweeperService.
class Jabvox::TaskDueSweeperJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Jabvox::TaskDueSweeperService.new.call
  end
end
