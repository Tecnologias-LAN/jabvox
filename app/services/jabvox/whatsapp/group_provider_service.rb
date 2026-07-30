# Talks to Meta's WhatsApp Groups API for one whatsapp_cloud inbox. Kept separate
# from the individual-message provider (which is hardcoded to recipient_type
# individual) so group semantics never leak into 1:1 sends and vice versa.
#
# All methods return a parsed Hash on success and raise Jabvox::Whatsapp::GroupApiError
# on a non-2xx response, so callers get a single, typed failure to surface.
class Jabvox::Whatsapp::GroupProviderService
  API_VERSION = 'v22.0'.freeze

  def initialize(channel)
    @channel = channel
  end

  # Create a group with an initial subject. Returns the group payload incl. its id.
  def create_group(name, description: nil)
    body = { subject: name }
    body[:description] = description if description.present?
    post("#{phone_path}/groups", body)
  end

  # Fetch/refresh the invite link participants use to join (invite-only).
  def invite_link(provider_group_id)
    get("#{group_path(provider_group_id)}/invite")
  end

  def update_metadata(provider_group_id, attrs)
    post(group_path(provider_group_id), attrs.compact)
  end

  def remove_participant(provider_group_id, phone_number)
    delete("#{group_path(provider_group_id)}/participants", { participants: [phone_number] })
  end

  def update_participant_role(provider_group_id, phone_number, role)
    post("#{group_path(provider_group_id)}/participants",
         { participant: phone_number, role: role })
  end

  # Send a text or template message to the group. recipient_type: group is the
  # only difference from an individual send.
  def send_text(provider_group_id, text)
    post("#{phone_path}/messages", {
           messaging_product: 'whatsapp',
           recipient_type: 'group',
           to: provider_group_id,
           type: 'text',
           text: { body: text }
         })
  end

  private

  attr_reader :channel

  def base_path
    "#{ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')}/#{API_VERSION}"
  end

  def phone_path
    "#{base_path}/#{channel.provider_config['phone_number_id']}"
  end

  def group_path(provider_group_id)
    "#{base_path}/#{provider_group_id}"
  end

  def headers
    { 'Authorization' => "Bearer #{channel.provider_config['api_key']}", 'Content-Type' => 'application/json' }
  end

  def post(url, body)
    handle(HTTParty.post(url, headers: headers, body: body.to_json))
  end

  def get(url)
    handle(HTTParty.get(url, headers: headers))
  end

  def delete(url, body)
    handle(HTTParty.delete(url, headers: headers, body: body.to_json))
  end

  def handle(response)
    return response.parsed_response if response.success?

    message = response.parsed_response.dig('error', 'message') if response.parsed_response.is_a?(Hash)
    raise Jabvox::Whatsapp::GroupApiError.new(message || 'WhatsApp Groups API request failed', response.code)
  end
end
