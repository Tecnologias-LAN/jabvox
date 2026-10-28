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

  # Un run vivo rara vez supera el `:timeout: 25s` de Sidekiq; 15 min es holgado
  # para no tocar nunca un run realmente en curso. Configurable por ENV.
  STALE_AFTER = ENV.fetch('JABVOX_FLOWS_STALE_RUN_MINUTES', '15').to_i.minutes

  def perform
    cutoff = STALE_AFTER.ago
    # `running`: murió a mitad de la ejecución. `pending`: su RunJob nunca arrancó.
    stale = JabvoxFlowRun.where(status: %i[running pending])
                         .where(created_at: ..cutoff)
    count = 0
    stale.find_each do |run|
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
end
