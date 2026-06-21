# TODO: lets use HTTParty instead of RestClient
class JabvoxHub
  DEFAULT_BASE_URL = 'https://hub.2.chatwoot.com'.freeze

  # Base URL for the push-notification relay. Point JABVOX_HUB_URL at your own
  # infrastructure so mobile push goes through your server instead of any
  # external hub. Falls back to the default only if the env var is unset.
  def self.base_url
    ENV.fetch('JABVOX_HUB_URL', DEFAULT_BASE_URL)
  end

  def self.ping_url
    "#{base_url}/ping"
  end

  def self.registration_url
    "#{base_url}/instances"
  end

  def self.push_notification_url
    "#{base_url}/send_push"
  end

  def self.events_url
    "#{base_url}/events"
  end

  def self.billing_base_url
    "#{base_url}/billing"
  end

  def self.installation_identifier
    identifier = InstallationConfig.find_by(name: 'INSTALLATION_IDENTIFIER')&.value
    identifier ||= InstallationConfig.create!(name: 'INSTALLATION_IDENTIFIER', value: SecureRandom.uuid).value
    identifier
  end

  def self.billing_url
    "#{billing_base_url}?installation_identifier=#{installation_identifier}"
  end

  def self.pricing_plan
    return 'community' unless JabvoxApp.enterprise?

    ENV.fetch('INSTALLATION_PRICING_PLAN', nil) ||
      InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN')&.value ||
      'community'
  end

  def self.pricing_plan_quantity
    return 0 unless JabvoxApp.enterprise?

    value = ENV.fetch('INSTALLATION_PRICING_PLAN_QUANTITY', nil) ||
            InstallationConfig.find_by(name: 'INSTALLATION_PRICING_PLAN_QUANTITY')&.value
    Integer(value, exception: false) || 0
  end

  def self.support_config
    {
      support_website_token: InstallationConfig.find_by(name: 'JABVOX_SUPPORT_WEBSITE_TOKEN')&.value,
      support_script_url: InstallationConfig.find_by(name: 'JABVOX_SUPPORT_SCRIPT_URL')&.value,
      support_identifier_hash: InstallationConfig.find_by(name: 'JABVOX_SUPPORT_IDENTIFIER_HASH')&.value
    }
  end

  def self.instance_config
    {
      installation_identifier: installation_identifier,
      installation_version: Jabvox.config[:version],
      installation_host: URI.parse(ENV.fetch('FRONTEND_URL', '')).host,
      installation_env: ENV.fetch('INSTALLATION_ENV', ''),
      edition: ENV.fetch('CW_EDITION', '')
    }
  end

  def self.instance_metrics
    {
      accounts_count: fetch_count(Account),
      users_count: fetch_count(User),
      inboxes_count: fetch_count(Inbox),
      conversations_count: fetch_count(Conversation),
      incoming_messages_count: fetch_count(Message.incoming),
      outgoing_messages_count: fetch_count(Message.outgoing),
      additional_information: {}
    }
  end

  def self.fetch_count(model)
    model.last&.id || 0
  end

  # Telemetry disabled: no instance data is sent to any external hub.
  def self.sync_with_hub
    nil
  end

  # Telemetry disabled: instances are not registered with any external hub.
  def self.register_instance(_company_name, _owner_name, _owner_email)
    nil
  end

  def self.send_push(fcm_options)
    send_push_with_response(fcm_options)
  rescue *ExceptionList::REST_CLIENT_EXCEPTIONS => e
    Rails.logger.error "Exception: #{e.message}"
  rescue StandardError => e
    JabvoxExceptionTracker.new(e).capture_exception
  end

  def self.send_push_with_response(fcm_options)
    info = { fcm_options: fcm_options }
    RestClient.post(push_notification_url, info.merge(instance_config).to_json, { content_type: :json, accept: :json })
  end

  # Telemetry disabled: no events are emitted to any external hub.
  def self.emit_event(_event_name, _event_data)
    nil
  end
end

JabvoxHub.singleton_class.prepend_mod_with('JabvoxHub')
