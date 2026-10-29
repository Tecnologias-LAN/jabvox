# frozen_string_literal: true

# Red de seguridad del motor de flujos: si un RunService muere a mitad (OOM,
# reinicio del servidor, worker caído), el run queda en `running` para siempre y
# NUNCA se reintenta — la guarda de idempotencia de RunJob (que rechaza runs que
# no estén `pending`/`waiting`) impide incluso que Sidekiq lo recupere. Igual un
# run `pending` cuyo RunJob se perdió antes de arrancar queda colgado.
#
# Este cron marca `failed` todo run atascado en `running`/`pending` desde hace
# demasiado, para que no quede huérfano y el usuario pueda relanzar el flujo. NO
# se reintenta automáticamente: los nodos no son idempotentes por paso, así que
# reencolar duplicaría efectos ya emitidos (mensajes, etiquetas, webhooks). Fallar
# es la opción segura — mismo criterio que LeadImport::StaleSyncReaperJob.
class Jabvox::Flows::StaleRunReaperJob < ApplicationJob
  queue_as :jabvox_flows_scheduled
  # Cron cada 5 min: sin reintentos, la siguiente pasada recoge lo que quede.
  sidekiq_options retry: 0

  # Un run vivo rara vez supera el `:timeout: 25s` de Sidekiq; 15 min es holgado
  # para no tocar nunca un run realmente en curso. Configurable por ENV.
  STALE_AFTER = ENV.fetch('JABVOX_FLOWS_STALE_RUN_MINUTES', '15').to_i.minutes

  def perform
    cutoff = STALE_AFTER.ago
    count = 0
    stale_runs(cutoff).find_each do |run|
      run.update_columns( # rubocop:disable Rails/SkipsModelValidations
        status: JabvoxFlowRun.statuses[:failed],
        error: 'Ejecución interrumpida (worker o servidor reiniciado). Relanza el flujo si es necesario.',
        finished_at: Time.current,
        updated_at: Time.current
      )
      count += 1
    end
    Rails.logger.info("[Flows::StaleRunReaper] runs liberados: #{count}") if count.positive?
  end

  private

  # Dos criterios de "atascado", para no reapear un run que acaba de reanudarse:
  #  - `pending`: nunca arrancó, se mide por `created_at`.
  #  - `running`: se mide por cuándo empezó ESTE tramo (`started_at`), no por
  #    `created_at`. Un run que esperó horas en `waiting` y se reanudó tiene
  #    `created_at` antiguo pero `started_at` reciente: con `created_at` se habría
  #    marcado failed mientras ejecutaba legítimamente. `started_at` nulo (dato
  #    viejo) cae a `created_at` como respaldo.
  def stale_runs(cutoff)
    pending = JabvoxFlowRun.where(status: :pending).where(created_at: ..cutoff)
    running = JabvoxFlowRun.where(status: :running)
                           .where('COALESCE(started_at, created_at) <= ?', cutoff)
    JabvoxFlowRun.where(id: pending.select(:id)).or(JabvoxFlowRun.where(id: running.select(:id)))
  end
end
