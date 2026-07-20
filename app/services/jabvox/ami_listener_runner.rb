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

      Rails.logger.info '🚀 [AmiListenerRunner] Starting supervisor (dynamic account scan)'
      @threads = {} # account_id => Thread
      supervise_loop
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
      ActiveRecord::Base.connection_pool.with_connection do
        Account.joins(:jabvox_voip_config).pluck(:id)
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
