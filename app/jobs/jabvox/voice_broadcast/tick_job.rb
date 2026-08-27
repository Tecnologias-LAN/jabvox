# frozen_string_literal: true

# Dispatcher del voice broadcast (cron cada minuto): encola un TickAccountJob por
# cada broadcast en 'running' en la cola aislada jabvox_broadcast, para que un
# broadcast lento no retrase a los demás ni al tick del minuto siguiente.
# El pacing fino (CPS y concurrencia) lo controla el DialEngine dentro de cada tick.
class Jabvox::VoiceBroadcast::TickJob < ApplicationJob
  queue_as :jabvox_broadcast

  BACKLOG_CEILING = 500

  def perform
    if queue_backlogged?
      Rails.logger.warn('[VoiceBroadcast::TickJob] backlog alto en jabvox_broadcast; salto esta corrida')
      return
    end

    enqueued = 0
    JabvoxVoiceBroadcast.running.select(:id).find_each do |broadcast|
      Jabvox::VoiceBroadcast::TickAccountJob.perform_later(broadcast.id)
      enqueued += 1
    rescue StandardError => e
      Rails.logger.error "[VoiceBroadcast::TickJob] no se pudo encolar broadcast=#{broadcast.id} #{e.class}: #{e.message}"
    end
    Rails.logger.info("[VoiceBroadcast::TickJob] ticks encolados: #{enqueued}") if enqueued.positive?
  end

  private

  def queue_backlogged?
    Sidekiq::Queue.new('jabvox_broadcast').size > BACKLOG_CEILING
  rescue StandardError
    false
  end
end
