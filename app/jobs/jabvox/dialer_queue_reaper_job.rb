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

  # Cuánto tiempo saltar una cuenta cuyo PBX no respondió, para no gastar el
  # connect-timeout en cada corrida contra servidores apagados. Al expirar se
  # reintenta sola (si encendieron el PBX, vuelve a reconciliarse).
  # P3: bajado de 5 min a 90s — con 5 min, un PBX que parpadea dejaba agentes
  # fantasma en cola hasta 5 min recibiendo llamadas tras desconectarse. 90s
  # equilibra no martillar un PBX apagado y no dejar fantasmas demasiado tiempo.
  UNREACHABLE_TTL = 90

  def perform
    total = 0
    Account.joins(:jabvox_voip_config).find_each do |account|
      next if pbx_unreachable_cached?(account.id)

      result = Jabvox::DialerQueueReconcilerService.reconcile_account(account)
      mark_unreachable(account.id) unless result[:reachable]
      total += result[:removed].to_i
    rescue StandardError => e
      Rails.logger.error("[DialerQueueReaper] cuenta=#{account.id} #{e.class}: #{e.message}")
    end
    Rails.logger.info("[DialerQueueReaper] miembros fantasma removidos: #{total}") if total.positive?
  end

  private

  def unreachable_key(account_id)
    "jabvox_dialer_pbx_unreachable_#{account_id}"
  end

  def pbx_unreachable_cached?(account_id)
    Redis::Alfred.get(unreachable_key(account_id)).present?
  rescue StandardError
    false
  end

  def mark_unreachable(account_id)
    Redis::Alfred.set(unreachable_key(account_id), Time.current.to_i, ex: UNREACHABLE_TTL)
  rescue StandardError => e
    Rails.logger.warn("[DialerQueueReaper] no se pudo cachear PBX caído cuenta=#{account_id} | #{e.message}")
  end
end
