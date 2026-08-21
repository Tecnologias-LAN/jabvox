# Delivers a queued bulk WhatsApp batch off the request cycle so 1000+ recipients and many
# concurrent batches don't block or time out the web request.
#
# NO usamos retry_on aquí a propósito: post_all re-postea TODOS los chunks desde el
# inicio, así que reintentar el job entero re-enviaría WhatsApp a destinatarios que ya
# los recibieron (duplicados). El reintento de fallos transitorios ya vive DENTRO del
# service, por chunk (post_chunk_with_retries). Si un chunk falla definitivamente, el
# batch queda 'failed' y el operador puede reenviar la audiencia pendiente/fallida.
class Jabvox::BulkWhatsappDeliverJob < ApplicationJob
  queue_as :jabvox_meta

  def perform(batch_id)
    batch = JabvoxBulkWhatsappBatch.find_by(id: batch_id)
    return unless batch
    return unless batch.account.feature_enabled?('jabvox_bulk_whatsapp')
    # No reenviar un batch que ya está en un estado terminal o en curso.
    return if %w[sent running failed].include?(batch.status_jabvox)

    Jabvox::BulkWhatsappDispatchService.deliver!(batch)
  rescue StandardError => e
    # El service ya marcó 'failed' y revocó el token; aquí solo evitamos que la
    # excepción re-propague y dispare un reintento del job (que duplicaría envíos).
    Rails.logger.error("[BulkWhatsappDeliver] batch=#{batch_id} #{e.class}: #{e.message}")
  end
end
