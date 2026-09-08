# frozen_string_literal: true

# Avanza la marcación de UN solo voice broadcast (fan-out desde TickJob).
# Idempotente: DialEngine.tick toma un lock por broadcast, así dos ticks
# solapados no doble-marcan.
#
# MARCACIÓN CONTINUA: un tick dura como máximo MAX_TICK_SECONDS (para no acaparar el
# worker). Si al terminar aún queda trabajo (pendientes o llamadas en vuelo), el job se
# RE-ENCOLA de inmediato en vez de esperar al cron del próximo minuto — así el pacing es
# fluido y no hay gaps de ~15s. El lock por broadcast del engine impide que el re-encolado
# y el cron se solapen y doble-marquen.
class Jabvox::VoiceBroadcast::TickAccountJob < ApplicationJob
  queue_as :jabvox_broadcast

  # Pequeño respiro antes de re-encolar, para no crear un bucle apretado si el engine
  # salió muy rápido (p.ej. solo quedaban reintentos aún en su intervalo de espera).
  REQUEUE_DELAY = 2

  def perform(broadcast_id)
    broadcast = JabvoxVoiceBroadcast.running.find_by(id: broadcast_id)
    return if broadcast.nil?

    engine = Jabvox::VoiceBroadcast::DialEngine.new(broadcast)
    engine.tick
    # Si aún hay trabajo, continuar sin esperar al cron (marcación continua).
    self.class.set(wait: REQUEUE_DELAY.seconds).perform_later(broadcast_id) if engine.more_work?
  rescue StandardError => e
    Rails.logger.error "[VoiceBroadcast::TickAccountJob] broadcast=#{broadcast_id} #{e.class}: #{e.message}"
  end
end
