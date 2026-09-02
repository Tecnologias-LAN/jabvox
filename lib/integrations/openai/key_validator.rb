module Integrations::Openai::KeyValidator
  TIMEOUT_SECONDS = 5

  # Validates the key against the provider's /models endpoint. `base_url` is the
  # per-hook base URL entered when connecting Jabvox IA; when blank it falls
  # back to the installation endpoint / OpenAI.
  def self.valid?(api_key, base_url = nil)
    return false if api_key.blank?

    connection = Faraday.new do |f|
      f.options.timeout = TIMEOUT_SECONDS
      f.options.open_timeout = TIMEOUT_SECONDS
    end

    response = connection.get("#{api_base(base_url)}/models") do |req|
      req.headers['Authorization'] = "Bearer #{api_key}"
    end

    response.status != 401
  rescue Faraday::Error => e
    Rails.logger.warn("[openai-key-validator] #{e.class}: #{e.message}")
    true
  end

  def self.api_base(base_url = nil)
    endpoint = base_url.presence ||
               InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value.presence ||
               'https://api.openai.com/'
    endpoint = endpoint.strip.chomp('/')
    endpoint.end_with?('/v1') ? endpoint : "#{endpoint}/v1"
  end
end
