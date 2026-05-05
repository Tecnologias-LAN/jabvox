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

      threads = account_ids.map do |account_id|
        Thread.new do
          Jabvox::AmiListenerService.new(account_id).run
        end
      end
      threads.each(&:join)
    end
  end
end
