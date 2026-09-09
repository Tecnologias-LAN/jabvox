# Detects whether a WhatsApp Cloud phone number is an Official Business Account
# (OBA / verified badge) by asking Meta's Graph API, and caches the answer on the
# channel's provider_config so the groups-eligibility check resolves on its own —
# no manual flag flipping per number.
#
# Meta exposes it on the phone number node:
#   GET /{phone_number_id}?fields=official_business_account
# The field is an OBJECT (its `status` is APPROVED/PENDING/… when a request exists,
# absent/empty when the number is not an OBA). We treat APPROVED as official.
#
# Only meaningful for whatsapp_cloud channels; other providers return false.
class Jabvox::Whatsapp::ObaStatusService
  API_VERSION = 'v22.0'.freeze
  CACHE_TTL = 12.hours

  def initialize(channel)
    @channel = channel
  end

  # Returns true/false. Uses the cached value unless it's stale or `force:`d, so
  # the eligibility check stays cheap (no Graph call on every page load).
  def official_business_account?(force: false)
    return false unless @channel.provider == 'whatsapp_cloud'
    return cached_value if !force && cache_fresh?

    refresh
  rescue StandardError => e
    Rails.logger.warn("[Jabvox WhatsApp OBA] #{@channel.id} #{e.class}: #{e.message}")
    cached_value # fall back to whatever we last knew
  end

  # Fetches from Meta and writes the result (+ timestamp) into provider_config.
  def refresh
    status = fetch_oba_status
    official = status_official?(status)
    persist(official, status)
    official
  end

  # Machine-readable OBA state as last seen from Meta (NOT_STARTED / PENDING /
  # APPROVED / REJECTED / …), for the UI to explain WHY groups are blocked and what
  # to do. Reads the cached raw payload; nil if never checked.
  def oba_status
    raw = provider_config['oba_status_raw']
    return nil unless raw.is_a?(Hash)

    (raw['oba_status'] || raw['status']).to_s.upcase.presence
  end

  private

  def cache_fresh?
    return false unless provider_config.key?('is_official_business_account')

    checked = provider_config['oba_checked_at']
    checked.present? && Time.zone.parse(checked.to_s) > CACHE_TTL.ago
  rescue ArgumentError, TypeError
    false
  end

  def cached_value
    ActiveModel::Type::Boolean.new.cast(provider_config['is_official_business_account'])
  end

  # GET /{phone_number_id}?fields=official_business_account
  def fetch_oba_status
    phone_id = provider_config['phone_number_id']
    return {} if phone_id.blank?

    url = "#{base_url}/#{API_VERSION}/#{phone_id}"
    resp = HTTParty.get(url, headers: auth_headers, query: { fields: 'official_business_account' })
    return {} unless resp.success?

    body = resp.parsed_response
    body.is_a?(Hash) ? (body['official_business_account'] || {}) : {}
  end

  # Meta returns an object; APPROVED status (or an explicit boolean true) = OBA.
  def status_official?(status)
    return ActiveModel::Type::Boolean.new.cast(status) unless status.is_a?(Hash)

    state = (status['status'] || status['oba_status']).to_s.upcase
    state == 'APPROVED' || ActiveModel::Type::Boolean.new.cast(status['is_official_business_account'])
  end

  def persist(official, status)
    cfg = provider_config.dup
    cfg['is_official_business_account'] = official
    cfg['oba_checked_at'] = Time.current.iso8601
    cfg['oba_status_raw'] = status if status.present?
    @channel.update_column(:provider_config, cfg) # rubocop:disable Rails/SkipsModelValidations
  end

  def provider_config
    @channel.provider_config || {}
  end

  def base_url
    ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
  end

  def auth_headers
    { 'Authorization' => "Bearer #{provider_config['api_key']}" }
  end
end
