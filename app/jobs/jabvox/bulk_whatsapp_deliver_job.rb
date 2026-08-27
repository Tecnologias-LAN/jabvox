# Delivers a queued bulk WhatsApp batch off the request cycle so 1000+ recipients and many
# concurrent batches don't block or time out the web request.
#
# NO usamos retry_on aquí a propósito: post_all re-postea TODOS los chunks desde el
# inicio, así que reintentar el job entero re-enviaría WhatsApp a destinatarios que ya
# los recibieron (duplicados). El reintento de fallos transitorios ya vive DENTRO del
# service, por chunk (post_chunk_with_retries). Si un chunk falla definitivamente, el
# batch queda 'failed' y el operador puede reenviar la audiencia pendiente/fallida.
class Jabvox::BulkWhatsappDeliverJob < ApplicationJob
  include Jabvox::AccountFairShare
  queue_as :jabvox_meta

  # Fairness: limita cuántos BATCHES de una misma cuenta corren a la vez en el worker
  # meta, para que una cuenta con muchos envíos masivos no acapare los slots (head-of-line
  # blocking) y bloquee a las demás. Batches pequeño por cuenta (default 2). Override ENV.
  fair_share_limit 2
  fair_share_env 'JABVOX_BULK_WA_MAX_INFLIGHT_PER_ACCOUNT'

  def perform(batch_id)
    batch = JabvoxBulkWhatsappBatch.find_by(id: batch_id)
    return unless batch
    return unless batch.account.feature_enabled?('jabvox_bulk_whatsapp')
    # No reenviar un batch que ya está en un estado terminal o en curso.
    return if %w[sent running failed].include?(batch.status_jabvox)

    with_account_fair_share(batch.account_id) do
      Jabvox::BulkWhatsappDispatchService.deliver!(batch)
    end
  rescue StandardError => e
    # El service ya marcó 'failed' y revocó el token; aquí solo evitamos que la
    # excepción re-propague y dispare un reintento del job (que duplicaría envíos).
    Rails.logger.error("[BulkWhatsappDeliver] batch=#{batch_id} #{e.class}: #{e.message}")
  end
end
