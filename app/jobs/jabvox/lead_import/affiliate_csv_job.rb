# frozen_string_literal: true

# Procesa el CSV que sube un afiliado, fuera del ciclo de request.
#
# Antes esto corría dentro del POST: 5.000 filas × (2 consultas + 2 inserts)
# bloqueaban un hilo de Puma varios minutos y, con varios afiliados subiendo a la
# vez, agotaban el pool de conexiones. Ahora el endpoint responde de inmediato con
# el registro de importación en estado 'processing' y el portal consulta el avance.
#
# Corre en la cola aislada de importaciones, con un lock por afiliado para que dos subidas simultáneas del
# mismo afiliado no se pisen creando duplicados.
class Jabvox::LeadImport::AffiliateCsvJob < ApplicationJob
  # Cola interactiva: el afiliado está mirando la barra de progreso, no puede
  # quedar detrás de una sincronización de BD externa (ver sidekiq_lead_import.yml).
  queue_as :jabvox_lead_import_interactive

  LOCK_TTL = 10.minutes.to_i
  # Se procesa por lotes para que el trabajo avance de forma visible y la
  # memoria no crezca con el tamaño del archivo.
  BATCH_SIZE = 200

  def perform(import_id)
    import = JabvoxAffiliateImport.find_by(id: import_id)
    return unless import&.processing?

    result = Jabvox::RedisLock.with_lock("jabvox:affiliate_import:#{import.jabvox_affiliate_id}", ttl: LOCK_TTL) do |lock|
      run_import(import, lock)
    end
    return unless result == Jabvox::RedisLock::NOT_ACQUIRED

    # Otra subida del mismo afiliado está en curso: se reintenta más tarde en
    # lugar de procesar en paralelo y arriesgar duplicados.
    Rails.logger.warn("[AffiliateImport] import=#{import_id} afiliado ocupado, reencolo")
    self.class.set(wait: 30.seconds).perform_later(import_id)
  end

  private

  def run_import(import, lock)
    rows = parse_rows(import)
    return import.update!(status: :failed, error_message: 'archivo_ilegible') if rows.nil?

    import.update!(rows_total: rows.size)
    counters = process(import, rows)
    finish(import, counters, lock)
  rescue StandardError => e
    Rails.logger.error("[AffiliateImport] import=#{import.id} #{e.class}: #{e.message}")
    import.update(status: :failed, error_message: 'error_interno')
  end

  def parse_rows(import)
    require 'csv'
    content = import.source_file.download.force_encoding('UTF-8')
    content = content.scrub('') unless content.valid_encoding?
    CSV.parse(content, headers: true, header_converters: :downcase, skip_blanks: true).map(&:to_h)
  rescue CSV::MalformedCSVError, ActiveStorage::FileNotFoundError
    nil
  end

  def process(import, rows)
    importer = Jabvox::AffiliateLeadImporter.new(
      account: import.account, affiliate: import.jabvox_affiliate,
      country_iso: import.country_jabvox, campaign_name: import.campaign_name_jabvox
    )

    rows.each_slice(BATCH_SIZE).with_index do |batch, idx|
      batch.each { |row| importer.import_row(row) }
      # Progreso visible en el portal mientras el archivo se procesa. El TTL del
      # lock lo renueva solo el heartbeat de RedisLock.
      import.update_columns(**importer.counters, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      Rails.logger.info("[AffiliateImport] import=#{import.id} lote=#{idx + 1} #{importer.counters.inspect}")
    end
    importer.counters
  end

  def finish(import, counters, lock)
    # Fencing: si perdimos el lock (proceso congelado más que el TTL y otro lo
    # tomó), no marcamos el resultado — manda el dueño actual del lock.
    return unless lock.held?

    import.update!(status: :completed, completed_at: Time.current, **counters)
  end
end
