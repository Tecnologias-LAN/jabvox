module Jabvox
  module AmiListenerRunner
    def self.start
      Rails.logger = ActiveSupport::Logger.new($stdout)
      Rails.logger.formatter = proc { |_sev, _time, _prog, msg| "#{msg}\n" }

      account_ids = Account.joins(:jabvox_voip_config).pluck(:id)
      Rails.logger.info "🚀 [AmiListenerRunner] Starting listeners for accounts: #{account_ids.inspect}"

      if account_ids.empty?
        Rails.logger.warn '⚠️  [AmiListenerRunner] No accounts with VoIP config found — exiting'
        return
      end

      # One isolated thread per account. A thread must NEVER die: if an account's
      # listener raises past its own reconnect loop (unexpected bug, or the PBX is
      # permanently unreachable), we log it and respawn that one thread after a
      # short delay — the other accounts' listeners keep running untouched.
      threads = account_ids.map { |account_id| supervised_thread(account_id) }
      threads.each(&:join)
    end

    def self.supervised_thread(account_id)
      Thread.new do
        loop do
          Jabvox::AmiListenerService.new(account_id).run
        rescue StandardError => e
          Rails.logger.error "❌ [AmiListenerRunner] account=#{account_id} thread crashed, respawning in 15s | #{e.class}: #{e.message}"
          sleep 15
        end
      end
    end
  end
end
