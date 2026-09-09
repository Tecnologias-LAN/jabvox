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

  # Create a group with an initial subject. Meta requires messaging_product on every
  # Groups API write. Returns the group payload incl. its id.
  # Ref: POST /<PHONE_NUMBER_ID>/groups { messaging_product, subject, description }
  def create_group(name, description: nil)
    body = { messaging_product: 'whatsapp', subject: name }
    body[:description] = description if description.present?
    post("#{phone_path}/groups", body)
  end

  # Fetch the invite link participants use to join (invite-only).
  # Ref: GET /<GROUP_ID>/invite_link
  def invite_link(provider_group_id)
    get("#{group_path(provider_group_id)}/invite_link")
  end

  # Reset (rotate) the invite link, invalidating the previous one.
  # Ref: POST /<GROUP_ID>/invite_link { messaging_product }
  def reset_invite_link(provider_group_id)
    post("#{group_path(provider_group_id)}/invite_link", { messaging_product: 'whatsapp' })
  end

  # Update group subject/description.
  # Ref: POST /<GROUP_ID> { messaging_product, subject, description }
  def update_metadata(provider_group_id, attrs)
    post(group_path(provider_group_id), attrs.compact.merge(messaging_product: 'whatsapp'))
  end

  # Remove a participant. Meta expects an array of { user: <phone|wa_id> } objects.
  # Ref: DELETE /<GROUP_ID>/participants { messaging_product, participants: [{ user }] }
  def remove_participant(provider_group_id, phone_number)
    delete("#{group_path(provider_group_id)}/participants",
           { messaging_product: 'whatsapp', participants: [{ user: phone_number }] })
  end

  # Send a text message to the group. recipient_type: group + the group id as `to`
  # is the only difference from an individual send.
  # Ref: POST /<PHONE_NUMBER_ID>/messages { recipient_type: 'group', to: <GROUP_ID> }
  def send_text(provider_group_id, text)
    post("#{phone_path}/messages", {
           messaging_product: 'whatsapp',
           recipient_type: 'group',
           to: provider_group_id,
           type: 'text',
           text: { preview_url: true, body: text }
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
