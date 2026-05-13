module Jabvox
  class SslProvisionJob < ApplicationJob
    queue_as :default
    sidekiq_options retry: 0

    def perform(form_config_id)
      config = JabvoxFormConfig.find(form_config_id)
      config.update_columns(ssl_status: 'provisioning', ssl_error: nil, updated_at: Time.current)
      Jabvox::SslProvisionService.new(config).call
    rescue ActiveRecord::RecordNotFound
      Rails.logger.warn("Jabvox::SslProvisionJob: JabvoxFormConfig #{form_config_id} not found")
    rescue StandardError
      # status already set to 'failed' by the service
    end
  end
end
