require 'httparty'

# Manages WhatsApp message templates via the Meta Graph API.
# Only supports Cloud API (whatsapp_cloud) channels; 360Dialog channels
# do not expose a template-management endpoint in the same way.
class Jabvox::WhatsappTemplateService
  WHATSAPP_API_VERSION = 'v14.0'.freeze

  def initialize(channel)
    @channel = channel
  end

  # Returns all templates stored in the channel (cached in DB) and optionally
  # re-fetches from Meta if force: true.
  def list(force_sync: false)
    @channel.sync_templates if force_sync
    @channel.reload.message_templates || []
  end

  # Creates a new template via Meta API.
  # params: { name:, category:, language:, components: [] }
  # Returns { success:, template_id:, status:, error: }
  def create(params)
    body = build_create_body(params)
    response = HTTParty.post(
      "#{business_account_path}/message_templates",
      headers: api_headers,
      body: body.to_json
    )
    if response.success?
      @channel.sync_templates
      { success: true, template_id: response['id'], status: response['status'] || 'PENDING' }
    else
      error_msg = response.parsed_response&.dig('error', 'message') || response.body
      { success: false, error: error_msg }
    end
  rescue StandardError => e
    { success: false, error: e.message }
  end

  # Deletes a template by name (all language variants).
  # Returns { success:, error: }
  def destroy(template_name)
    response = HTTParty.delete(
      "#{business_account_path}/message_templates?name=#{template_name}",
      headers: api_headers
    )
    if response.success?
      @channel.sync_templates
      { success: true }
    else
      error_msg = response.parsed_response&.dig('error', 'message') || response.body
      { success: false, error: error_msg }
    end
  rescue StandardError => e
    { success: false, error: e.message }
  end

  # Fetches live status for a single template by name from Meta.
  def fetch_status(template_name)
    response = HTTParty.get(
      "#{business_account_path}/message_templates?name=#{template_name}",
      headers: api_headers
    )
    return { success: false, error: 'Request failed' } unless response.success?

    data = response.parsed_response&.dig('data')&.first
    return { success: false, error: 'Not found' } unless data

    { success: true, status: data['status'], id: data['id'], name: data['name'] }
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def cloud_api?
    @channel.provider == 'whatsapp_cloud'
  end

  private

  def build_create_body(params)
    {
      name: params[:name].to_s.downcase.gsub(/[^a-z0-9_]/, '_'),
      category: params[:category].to_s.upcase,
      language: params[:language] || 'es',
      components: params[:components] || []
    }
  end

  def business_account_path
    "#{api_base}/#{WHATSAPP_API_VERSION}/#{@channel.provider_config['business_account_id']}"
  end

  def api_headers
    {
      'Authorization' => "Bearer #{@channel.provider_config['api_key']}",
      'Content-Type' => 'application/json'
    }
  end

  def api_base
    ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
  end
end
