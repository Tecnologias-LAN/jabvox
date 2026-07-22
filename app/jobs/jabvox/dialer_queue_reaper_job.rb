# frozen_string_literal: true

# Reaper de miembros fantasma en las colas del dialer (cron cada 1 min).
#
# Un agente entra a la cola de Asterisk al conectarse al dialer y solo debería
# salir al desconectarse. Pero si cierra el navegador, se le cae la red o su
# sesión Redis expira, el `disconnect` nunca se ejecuta y queda como miembro
# fantasma: Asterisk le sigue enviando llamadas aunque ya NO esté conectado.
#
# Este job aplica la regla estricta "si no está conectado a la campaña, no puede
# estar en su cola": por cada cuenta con VoIP, reconcilia las colas reales de
# Asterisk contra las sesiones activas en Redis y quita a los fantasma. Solo
# ejecuta QueueRemove de miembros; nunca toca ni elimina colas.
class Jabvox::DialerQueueReaperJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    total = 0
    Account.joins(:jabvox_voip_config).find_each do |account|
      total += Jabvox::DialerQueueReconcilerService.reconcile_account(account)
    rescue StandardError => e
      Rails.logger.error("[DialerQueueReaper] cuenta=#{account.id} #{e.class}: #{e.message}")
    end
    Rails.logger.info("[DialerQueueReaper] miembros fantasma removidos: #{total}") if total.positive?
  end
end
