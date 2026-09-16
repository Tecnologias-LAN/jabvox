require 'httparty'

# Graph API lifecycle client for WhatsApp Flows (architecture doc section 5.3).
# Analogous to Jabvox::WhatsappTemplatesManager's Meta-facing half, but scoped to
# Flow create/update/publish/deprecate/fetch instead of templates. Same style:
# HTTParty, { success:, error:/... } returns, meta_error for readable messages
# that never leak the access token.
class Jabvox::WhatsappFlows::MetaClient
  def initialize(flow)
    @flow = flow
    @channel = flow.inbox&.channel
  end

  def create
    return unavailable unless cloud_channel?

    response = HTTParty.post(
      "#{waba_path}/flows",
      headers: api_headers,
      body: { name: @flow.name, categories: [@flow.category] }.to_json
    )
    return { success: false, error: meta_error(response) } unless response.success?

    { success: true, meta_flow_id: response.parsed_response['id'] }
  rescue StandardError => e
    log_error('create', e)
    { success: false, error: e.message }
  end

  def update_metadata
    return unavailable unless cloud_channel?
    return missing_meta_flow_id unless @flow.meta_flow_id.present?

    response = HTTParty.post(
      "#{graph_base}/#{@flow.meta_flow_id}",
      headers: api_headers,
      body: { name: @flow.name, categories: [@flow.category] }.to_json
    )
    return { success: false, error: meta_error(response) } unless response.success?

    { success: true }
  rescue StandardError => e
    log_error('update_metadata', e)
    { success: false, error: e.message }
  end

  def update_json(flow_json)
    return unavailable unless cloud_channel?
    return missing_meta_flow_id unless @flow.meta_flow_id.present?

    tempfile = Tempfile.new(['flow', '.json'])
    tempfile.write(flow_json.to_json)
    tempfile.rewind

    response = HTTParty.post(
      "#{graph_base}/#{@flow.meta_flow_id}/assets",
      headers: { 'Authorization' => "Bearer #{access_token}" },
      body: {
        name: 'flow.json',
        asset_type: 'FLOW_JSON',
        file: File.open(tempfile.path, 'rb')
      }
    )
    return { success: false, error: meta_error(response) } unless response.success?

    { success: true, validation_errors: response.dig('validation_errors') || [] }
  rescue StandardError => e
    log_error('update_json', e)
    { success: false, error: e.message }
  ensure
    tempfile&.close
    tempfile&.unlink
  end

  def publish
    return unavailable unless cloud_channel?
    return missing_meta_flow_id unless @flow.meta_flow_id.present?

    response = HTTParty.post("#{graph_base}/#{@flow.meta_flow_id}/publish", headers: api_headers)
    return { success: false, error: meta_error(response) } unless response.success?

    { success: true }
  rescue StandardError => e
    log_error('publish', e)
    { success: false, error: e.message }
  end

  def deprecate
    return unavailable unless cloud_channel?
    return missing_meta_flow_id unless @flow.meta_flow_id.present?

    response = HTTParty.post("#{graph_base}/#{@flow.meta_flow_id}/deprecate", headers: api_headers)
    return { success: false, error: meta_error(response) } unless response.success?

    { success: true }
  rescue StandardError => e
    log_error('deprecate', e)
    { success: false, error: e.message }
  end

  FETCH_FIELDS = 'id,name,status,categories,validation_errors,json_version,data_api_version,endpoint_uri,preview'.freeze

  def fetch_status
    return unavailable unless cloud_channel?
    return missing_meta_flow_id unless @flow.meta_flow_id.present?

    response = HTTParty.get(
      "#{graph_base}/#{@flow.meta_flow_id}",
      headers: api_headers, query: { fields: FETCH_FIELDS }
    )
    return { success: false, error: meta_error(response) } unless response.success?

    { success: true, data: response.parsed_response }
  rescue StandardError => e
    log_error('fetch_status', e)
    { success: false, error: e.message }
  end

  def preview_url
    return unavailable unless cloud_channel?
    return missing_meta_flow_id unless @flow.meta_flow_id.present?

    response = HTTParty.get(
      "#{graph_base}/#{@flow.meta_flow_id}",
      headers: api_headers, query: { fields: 'preview.invalidate(false)' }
    )
    return { success: false, error: meta_error(response) } unless response.success?

    { success: true, url: response.dig('preview', 'preview_url') }
  rescue StandardError => e
    log_error('preview_url', e)
    { success: false, error: e.message }
  end

  # Meta only allows deleting a Flow while it's still in DRAFT on their side —
  # irreversible once PUBLISHED (architecture doc 2.1).
  def delete
    return unavailable unless cloud_channel?
    return missing_meta_flow_id unless @flow.meta_flow_id.present?
    return { success: false, error: 'Solo se puede eliminar un Flow en estado DRAFT en Meta' } unless @flow.meta_status == 'DRAFT'

    response = HTTParty.delete("#{graph_base}/#{@flow.meta_flow_id}", headers: api_headers)
    return { success: false, error: meta_error(response) } unless response.success?

    { success: true }
  rescue StandardError => e
    log_error('delete', e)
    { success: false, error: e.message }
  end

  private

  def unavailable
    { success: false, error: 'El inbox no es un canal de WhatsApp Cloud' }
  end

  def missing_meta_flow_id
    { success: false, error: 'El Flow todavía no fue creado en Meta' }
  end

  def cloud_channel?
    @channel.is_a?(Channel::Whatsapp) && @channel.provider == 'whatsapp_cloud'
  end

  def access_token
    @channel.provider_config['api_key']
  end

  def api_headers
    { 'Authorization' => "Bearer #{access_token}", 'Content-Type' => 'application/json' }
  end

  def api_version
    GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')
  end

  def api_base
    ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
  end

  def graph_base
    "#{api_base}/#{api_version}"
  end

  def waba_path
    "#{graph_base}/#{@flow.waba_id}"
  end

  # Same shape as WhatsappTemplatesManager#meta_error: prefers Meta's human-readable
  # fields, never includes the access token (which never appears in the response body
  # to begin with — it's only ever sent in the Authorization header).
  def meta_error(response)
    parsed = response.parsed_response
    err = parsed.is_a?(Hash) ? (parsed['error'] || {}) : {}
    parts = [
      err['error_user_title'],
      err['error_user_msg'],
      err.dig('error_data', 'details'),
      err['message']
    ].compact.uniq
    parts.any? ? parts.join(' — ') : (response.body.presence || 'Meta request failed')
  end

  def log_error(action, error)
    Rails.logger.error "[WA Flows] MetaClient##{action} failed for flow=#{@flow.id}: #{error.message}"
  end
end
