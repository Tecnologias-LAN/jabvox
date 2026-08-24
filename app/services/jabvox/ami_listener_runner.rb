module Jabvox
  module AmiListenerRunner
    # Cada cuánto re-escanear la BD por cuentas con VoIP nuevas/eliminadas, para
    # arrancar/parar listeners SIN reiniciar el proceso (antes las cuentas se
    # calculaban una sola vez al boot: una cuenta que configuraba VoIP después no
    # recibía eventos hasta el siguiente deploy).
    RESCAN_INTERVAL = 60

    def self.start
      Rails.logger = ActiveSupport::Logger.new($stdout)
      Rails.logger.formatter = proc { |_sev, _time, _prog, msg| "#{msg}\n" }

      Rails.logger.info "🚀 [AmiListenerRunner] Starting supervisor (dynamic account scan) " \
                        "shard #{shard_index}/#{shard_count}"
      @threads = {} # account_id => Thread
      supervise_loop
    end

    # Escala horizontal por SHARDING: se pueden correr N procesos de listener; cada
    # uno atiende SOLO las cuentas cuyo (account_id % shard_count == shard_index). Así
    # cada cuenta la escucha EXACTAMENTE un proceso (sin eventos duplicados) y la carga
    # de miles de cuentas VoIP se reparte. Config por ENV en cada unidad systemd:
    #   JABVOX_AMI_LISTENER_SHARD_COUNT (total de procesos, default 1)
    #   JABVOX_AMI_LISTENER_SHARD_INDEX (índice de ESTE proceso, 0..count-1, default 0)
    # Con los valores por defecto (1/0) el comportamiento es idéntico al de un solo proceso.
    def self.shard_count
      [ENV.fetch('JABVOX_AMI_LISTENER_SHARD_COUNT', 1).to_i, 1].max
    end

    def self.shard_index
      idx = ENV.fetch('JABVOX_AMI_LISTENER_SHARD_INDEX', 0).to_i
      idx.clamp(0, shard_count - 1)
    end

    def self.owns_account?(account_id)
      (account_id % shard_count) == shard_index
    end

    # Bucle supervisor: cada RESCAN_INTERVAL sincroniza los threads con las
    # cuentas que tienen VoIP config (arranca las nuevas, deja morir las que ya
    # no aplican). Nunca termina.
    def self.supervise_loop
      loop do
        sync_threads
        sleep RESCAN_INTERVAL
      rescue StandardError => e
        Rails.logger.error "❌ [AmiListenerRunner] supervisor error | #{e.class}: #{e.message}"
        sleep RESCAN_INTERVAL
      end
    end

    def self.sync_threads
      desired = current_account_ids
      running = @threads.select { |_id, th| th.alive? }.keys

      (desired - running).each { |id| @threads[id] = supervised_thread(id) }
      # Limpia referencias a threads muertos (se re-crean arriba si siguen deseados).
      @threads.delete_if { |_id, th| !th.alive? }

      Rails.logger.info "🔄 [AmiListenerRunner] listeners activos: #{@threads.keys.sort.inspect}" if desired.sort != running.sort
    end

    def self.current_account_ids
      # Envuelve la query en una conexión del pool que se devuelve al terminar
      # (no la retiene de por vida como sí hacen los threads de listener).
      # Filtra por el shard de ESTE proceso: solo las cuentas que le tocan.
      ActiveRecord::Base.connection_pool.with_connection do
        Account.joins(:jabvox_voip_config).pluck(:id).select { |id| owns_account?(id) }
      end
    rescue StandardError => e
      Rails.logger.error "❌ [AmiListenerRunner] account scan failed | #{e.message}"
      []
    end

    def self.supervised_thread(account_id)
      Thread.new do
        loop do
          # with_connection: el listener toma una conexión del pool mientras corre
          # y la libera si el thread termina, en vez de retenerla para siempre
          # (evitaba agotar el pool cuando hay más cuentas que conexiones).
          ActiveRecord::Base.connection_pool.with_connection do
            Jabvox::AmiListenerService.new(account_id).run
          end
        rescue StandardError => e
          Rails.logger.error "❌ [AmiListenerRunner] account=#{account_id} thread crashed, respawning in 15s | #{e.class}: #{e.message}"
          sleep 15
        end
      end
    end
  end
end
