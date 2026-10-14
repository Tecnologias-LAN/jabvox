# Borra el token efímero de un envío masivo cuando ya no hace falta. Es el respaldo por si
# el callback final de n8n nunca llega; la vía normal es que el batch lo revoque al cerrar.
#
# NO borra el token si su envío sigue vivo: destruirlo a mitad deja a n8n enviando con una
# credencial muerta y cada mensaje restante falla con "401 Invalid Access Token". El envío
# 191 perdió así 341 destinatarios por el cierre prematuro del batch; este job podía causar
# lo mismo por tiempo en un envío más lento de lo calculado. Si todavía hay destinatarios
# pendientes, se reprograma en vez de borrar.
class Jabvox::BulkWhatsappTokenCleanupJob < ApplicationJob
  queue_as :jabvox_meta

  REINTENTO = 30.minutes
  # Tope de reprogramaciones: si algo deja el batch colgado para siempre, el token no
  # puede quedar vivo indefinidamente.
  MAX_REINTENTOS = 12

  def perform(access_token_id, intento = 0)
    batch = JabvoxBulkWhatsappBatch.find_by(access_token_id_jabvox: access_token_id)
    return AccessToken.where(id: access_token_id).destroy_all if batch.nil?

    if envio_en_curso?(batch) && intento < MAX_REINTENTOS
      self.class.set(wait: REINTENTO).perform_later(access_token_id, intento + 1)
      return
    end

    AccessToken.where(id: access_token_id).destroy_all
    batch.update_column(:access_token_id_jabvox, nil) # rubocop:disable Rails/SkipsModelValidations
  end

  private

  def envio_en_curso?(batch)
    batch.recipients.exists?(status_jabvox: 'pending')
  end
end
