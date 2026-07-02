# Delivers a queued bulk WhatsApp batch off the request cycle so 1000+ recipients and many
# concurrent batches don't block or time out the web request. Retries a few times on transient
# failures (the service also retries per-chunk); after that the batch is left marked 'failed'.
class Jabvox::BulkWhatsappDeliverJob < ApplicationJob
  queue_as :scheduled_jobs

  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(batch_id)
    batch = JabvoxBulkWhatsappBatch.find_by(id: batch_id)
    return unless batch
    return unless batch.account.feature_enabled?('jabvox_bulk_whatsapp')
    # Don't re-send a batch that already completed (guards against duplicate enqueues).
    return if batch.status_jabvox == 'sent'

    Jabvox::BulkWhatsappDispatchService.deliver!(batch)
  end
end
