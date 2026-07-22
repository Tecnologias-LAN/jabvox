# frozen_string_literal: true

# Sincroniza el CDR del PBX (MySQL externo) hacia la tabla local
# jabvox_cdr_records, enriquecido con los datos de Jabvox (número real del dialer,
# medio, agente, tipificación). El reporte lee de la tabla local para filtrar y
# paginar de forma exacta a cualquier volumen.
#
# Garantías:
#  - Incremental: avanza por calldate desde last_synced_calldate. La 1a corrida
#    hace backfill del histórico en lotes (no de un golpe).
#  - Idempotente: upsert por (account_id, uniqueid). Reprocesar el mismo lote no
#    duplica ni corrompe. Se solapa un margen de tiempo (OVERLAP) para no perder
#    filas que llegan al CDR con calldate en el borde del cursor.
#  - Resiliente: si el PBX está caído/inalcanzable, no avanza el cursor y reintenta
#    en la siguiente corrida (cuando vuelva, retoma donde quedó). No lanza.
#  - Aislado por cuenta: el job llama a este servicio por cuenta; un fallo aquí se
#    captura y devuelve un resultado, nunca propaga a otras cuentas.
module Jabvox
  class CdrSyncService
    BATCH_LIMIT = 1000
    # Reprocesa este margen antes del cursor: cubre filas que el PBX escribe con
    # unos segundos de desfase respecto al calldate ya sincronizado (upsert las
    # deduplica, así que reprocesar es seguro).
    OVERLAP = 120 # segundos
    # Tope de lotes por corrida, para que el backfill de un histórico enorme no
    # monopolice el worker; las corridas siguientes continúan.
    MAX_BATCHES_PER_RUN = 20

    def self.sync_account(account)
      new(account).sync
    end

    def initialize(account)
      @account = account
      @config = account.jabvox_cdr_config
    end

    # Devuelve { ok:, inserted:, updated:, reachable: }. Registra la corrida en
    # jabvox_cdr_sync_runs (auditoría/monitoreo) pase lo que pase.
    def sync
      @run = { started_at: Time.current, started_mono: monotonic,
               inserted: 0, updated: 0, skipped: 0, errors: 0, fetched: 0,
               cursor_before: @config&.last_synced_calldate, error_message: nil }

      return finish(skip('sin config MySQL'), 'skipped') if @config&.mysql_host.blank?

      mysql = Jabvox::CdrMysqlService.new(@config, account: @account)
      return finish(unreachable, 'unreachable') unless mysql_reachable?(mysql)

      run_batches(mysql)
      finish({ ok: true, reachable: true, inserted: @run[:inserted], updated: @run[:updated] }, 'ok')
    rescue StandardError => e
      fail_run(e)
    end

    private

    # Procesa hasta MAX_BATCHES_PER_RUN lotes incrementales, avanzando el cursor
    # tras cada lote. Se detiene al agotar filas nuevas o al llegar al tope.
    def run_batches(mysql)
      cursor = start_cursor
      MAX_BATCHES_PER_RUN.times do
        rows = mysql.fetch_batch_since(cursor, limit: BATCH_LIMIT)
        break if rows.empty?

        @run[:fetched] += rows.size
        upsert_batch(rows)
        cursor = cursor_string(rows.last[:calldate])
        advance_cursor(cursor)
        break if rows.size < BATCH_LIMIT # no hay más por ahora
      end
    end

    # Registra la corrida como fallida (con el error saneado) y devuelve el result.
    def fail_run(err)
      Rails.logger.error "[CdrSync] cuenta=#{@account.id} #{err.class}: #{err.message}"
      @run[:error_message] = safe_error(err)
      @run[:errors] += 1
      finish({ ok: false, reachable: false, inserted: @run[:inserted],
               updated: @run[:updated], error: err.message }, 'error')
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    # Persiste la fila de auditoría de esta corrida y devuelve el result recibido.
    def finish(result, status)
      JabvoxCdrSyncRun.create!(
        account_id: @account.id,
        started_at: @run[:started_at],
        finished_at: Time.current,
        duration_ms: ((monotonic - @run[:started_mono]) * 1000).round,
        pbx_reachable: result[:reachable] != false,
        inserted_count: @run[:inserted],
        updated_count: @run[:updated],
        skipped_count: @run[:skipped],
        error_count: @run[:errors],
        fetched_count: @run[:fetched],
        cursor_before: @run[:cursor_before],
        cursor_after: @config&.reload&.last_synced_calldate,
        status: status,
        error_message: @run[:error_message]
      )
      result
    rescue StandardError => e
      # La auditoría nunca debe tumbar la sincronización.
      Rails.logger.error "[CdrSync] no se pudo registrar la corrida cuenta=#{@account.id} | #{e.message}"
      result
    end

    # Cursor de arranque como STRING 'YYYY-MM-DD HH:MM:SS' (formato del CDR), menos
    # el OVERLAP para recapturar filas de borde. nil en la 1a corrida => backfill.
    # Se compara como texto contra el CDR, sin conversiones de zona horaria.
    def start_cursor
      raw = @config.last_synced_cursor
      return nil if raw.blank?

      # Restar el solape parseando el string en la MISMA zona (sin desplazar):
      # Time.parse conserva los componentes, restamos segundos y reformateamos.
      (Time.zone.parse(raw) - OVERLAP).strftime('%Y-%m-%d %H:%M:%S')
    rescue StandardError
      # Si el cursor guardado no fuera parseable, arrancar sin cursor (backfill),
      # el upsert idempotente evita duplicados.
      nil
    end

    # Convierte el calldate (Time de mysql2, hora del PBX) al string del CDR.
    def cursor_string(calldate)
      return nil if calldate.blank?

      calldate.respond_to?(:strftime) ? calldate.strftime('%Y-%m-%d %H:%M:%S') : calldate.to_s
    end

    def advance_cursor(cursor)
      return if cursor.blank?

      # Solo avanza (nunca retrocede) el cursor persistido. Comparación de strings
      # en formato 'YYYY-MM-DD HH:MM:SS' (lexicográfico == cronológico).
      current = @config.last_synced_cursor
      return if current.present? && cursor <= current

      # Persistimos el cursor textual (fuente de verdad) y, por comodidad del
      # monitor, tambien la fecha para mostrarla.
      @config.update_columns( # rubocop:disable Rails/SkipsModelValidations
        last_synced_cursor: cursor,
        last_synced_calldate: parse_cursor(cursor)
      )
    end

    def parse_cursor(cursor)
      Time.zone.parse(cursor)
    rescue StandardError
      nil
    end

    def upsert_batch(rows)
      rows.each do |r|
        uid = r[:uniqueid].to_s
        if uid.blank?
          @run[:skipped] += 1
          next
        end

        rec = JabvoxCdrRecord.find_or_initialize_by(account_id: @account.id, uniqueid: uid)
        new_record = rec.new_record?
        rec.assign_attributes(attributes_from(r))
        rec.save!
        new_record ? (@run[:inserted] += 1) : (@run[:updated] += 1)
      rescue StandardError => e
        # Una fila mala no aborta el lote entero.
        @run[:errors] += 1
        @run[:error_message] ||= "fila uid=#{r[:uniqueid]}: #{safe_error(e)}"
        Rails.logger.warn "[CdrSync] cuenta=#{@account.id} fila uid=#{r[:uniqueid]} #{e.message}"
      end
    end

    def attributes_from(row) # rubocop:disable Metrics/MethodLength
      {
        linkedid: row[:linkedid],
        calldate: row[:calldate],
        src: row[:src],
        dst: row[:dst],
        channel: row[:channel_raw],
        dstchannel: row[:dstchannel_raw],
        disposition: row[:disposition],
        duration: row[:duration].to_i,
        billsec: row[:billsec].to_i,
        recordingfile: row[:recording_file],
        origin: row[:origin],
        destination: row[:destination],
        origin_channel: row[:origin_channel],
        agent_extension: row[:agent_extension],
        medium: row[:medium],
        agent_name: row[:agent_name],
        typification_id: row[:typification_id],
        typification: row[:typification]
      }
    end

    # Chequeo rápido de conectividad al PBX; si no responde, no tocamos el cursor.
    def mysql_reachable?(mysql)
      res = mysql.test_connection
      res[:success]
    rescue StandardError
      false
    end

    # El error_message se persiste en la auditoría y lo ve el admin de la cuenta en
    # el monitor. Los mensajes de Mysql2/Net::SSH suelen incluir host, usuario,
    # puerto o IP del PBX (reconocimiento de infraestructura). Conservamos la clase
    # del error y el texto, pero redactamos IPs, host:puerto y credenciales.
    def safe_error(err)
      msg = err.message.to_s.dup
      msg.gsub!(/\b\d{1,3}(?:\.\d{1,3}){3}\b/, '[host]')          # IPv4
      msg.gsub!(/(host|server)\s*=?\s*'?[\w.\-]+'?/i, '\1=[host]') # host=...
      msg.gsub!(/:\d{2,5}\b/, ':[port]')                          # :puerto
      msg.gsub!(/(user|username|password)\s*=?\s*'?[^\s']+'?/i, '\1=[redacted]')
      "#{err.class}: #{msg}".truncate(500)
    end

    def skip(reason)
      Rails.logger.info "[CdrSync] cuenta=#{@account.id} omitida: #{reason}"
      { ok: true, reachable: true, inserted: 0, updated: 0, skipped: reason }
    end

    def unreachable
      Rails.logger.info "[CdrSync] cuenta=#{@account.id} PBX inalcanzable, se reintenta luego"
      { ok: false, reachable: false, inserted: 0, updated: 0 }
    end
  end
end
