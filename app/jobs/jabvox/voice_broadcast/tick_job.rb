# frozen_string_literal: true

# Motor del voice broadcast por tick (cron cada minuto). Recorre los broadcasts en
# 'running' de TODAS las cuentas y avanza la marcación de cada uno según su pacing.
# Aislado por broadcast: un fallo en uno no corta los demás. Idempotente: el propio
# DialEngine toma un lock por broadcast, así dos ticks solapados no doble-marcan.
#
# Nota de cadencia: el mínimo de sidekiq-cron es 1 minuto. El pacing fino (CPS y
# concurrencia) lo controla el DialEngine DENTRO de cada tick; para ritmos más altos
# se sube max_concurrent/cps del broadcast, no la frecuencia del cron.
class Jabvox::VoiceBroadcast::TickJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    JabvoxVoiceBroadcast.running.find_each do |broadcast|
      Jabvox::VoiceBroadcast::DialEngine.tick(broadcast)
    rescue StandardError => e
      Rails.logger.error "[VoiceBroadcast::TickJob] broadcast=#{broadcast.id} #{e.class}: #{e.message}"
    end
  end
end
