# frozen_string_literal: true

# Avanza la marcación de UN solo voice broadcast (fan-out desde TickJob).
# Idempotente: DialEngine.tick toma un lock por broadcast, así dos ticks
# solapados no doble-marcan.
class Jabvox::VoiceBroadcast::TickAccountJob < ApplicationJob
  queue_as :jabvox_broadcast

  def perform(broadcast_id)
    broadcast = JabvoxVoiceBroadcast.running.find_by(id: broadcast_id)
    return if broadcast.nil?

    Jabvox::VoiceBroadcast::DialEngine.tick(broadcast)
  rescue StandardError => e
    Rails.logger.error "[VoiceBroadcast::TickAccountJob] broadcast=#{broadcast_id} #{e.class}: #{e.message}"
  end
end
