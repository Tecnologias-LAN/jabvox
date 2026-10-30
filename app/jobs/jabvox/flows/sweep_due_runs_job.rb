# frozen_string_literal: true

# Despierta los runs suspendidos cuyo instante de reanudación ya pasó. Es la red
# de seguridad del `delay` / `wait_until`: aunque se pierda el job puntual, el
# barrido periódico los recoge y ninguno queda colgado para siempre.
class Jabvox::Flows::SweepDueRunsJob < ApplicationJob
  queue_as :jabvox_flows_scheduled
  # Cron cada minuto: si una pasada falla, la siguiente recoge lo mismo.
  # NO usar `sidekiq_options` (no existe en ApplicationJob; rompía con 'jid=' al
  # invocarlo desde sidekiq-cron).

  def perform(limit = 50)
    JabvoxFlowRun.due.order(:resume_at).limit(limit).pluck(:id).each do |run_id|
      Jabvox::Flows::ResumeRunJob.perform_later(run_id)
    end
  end
end
