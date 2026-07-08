require 'httparty'
require 'csv'

class Jabvox::WhatsappTemplatesManager
  # Graph API version, overridable via env to stay in step with the rest of the app.
  DEFAULT_API_VERSION = 'v22.0'.freeze
  PER_PAGE = 50

  def initialize(account, user: nil)
    @account = account
    @user = user
  end

  def list(filters: {}, page: 1, per_page: PER_PAGE)
    scope = @account.jabvox_whatsapp_templates.includes(:inbox, :created_by)
    scope = scope.by_inbox(filters[:inbox_id])
    scope = scope.where(status: filters[:status]) if filters[:status].present?
    scope = scope.where(category: filters[:category]) if filters[:category].present?
    scope = scope.where(language: filters[:language]) if filters[:language].present?
    scope = scope.search_text(filters[:q])
    scope = scope.where('jabvox_whatsapp_templates.created_at >= ?', filters[:date_from]) if filters[:date_from].present?
    scope = scope.where('jabvox_whatsapp_templates.created_at <= ?', filters[:date_to]) if filters[:date_to].present?
    total = scope.count
    records = scope.order(created_at: :desc).offset((page.to_i - 1) * per_page.to_i).limit(per_page.to_i)
    { templates: records, total: total, page: page.to_i, per_page: per_page.to_i }
  end

  def find(id)
    @account.jabvox_whatsapp_templates.find(id)
  end

  def metrics(inbox_id: nil)
    scope = @account.jabvox_whatsapp_templates
    scope = scope.where(inbox_id: inbox_id) if inbox_id.present?
    counts = scope.group(:status).count
    quality = scope.group(:quality_score).count
    {
      total: counts.values.sum,
      approved: counts['APPROVED'] || 0,
      pending: counts['PENDING'] || 0,
      rejected: counts['REJECTED'] || 0,
      paused: counts['PAUSED'] || 0,
      disabled: counts['DISABLED'] || 0,
      quality_high: quality['GREEN'] || 0,
      quality_medium: quality['YELLOW'] || 0,
      quality_low: quality['RED'] || 0
    }
  end

  # How long a channel's synced templates are considered fresh; auto-sync skips channels
  # refreshed more recently than this to avoid hammering Meta on every page load.
  STALE_AFTER = 2.minutes

  # Syncs every WhatsApp Cloud inbox of the account with Meta, so template statuses
  # (pending -> approved/rejected) refresh without picking a specific inbox. Isolated per
  # inbox so one failing inbox doesn't abort the rest. Pass only_stale: true (used by the
  # on-open auto-sync) to skip channels that were refreshed within STALE_AFTER.
  def sync_all_inboxes(only_stale: false)
    total = 0
    synced_inboxes = 0
    whatsapp_cloud_inboxes.find_each do |inbox|
      next if only_stale && fresh?(inbox.channel)

      result = sync_inbox(inbox)
      if result[:success]
        total += result[:synced].to_i
        synced_inboxes += 1
      end
    end
    { success: true, synced: total, inboxes: synced_inboxes }
  end

  def sync_inbox(inbox)
    channel = inbox.channel
    return { success: false, error: 'Not a WhatsApp Cloud inbox' } unless cloud_channel?(channel)

    raw_templates = fetch_all_from_meta(channel)
    synced = 0
    raw_templates.each do |raw|
      upsert_from_meta(raw, inbox)
      synced += 1
    end
    channel.update(message_templates: raw_templates, message_templates_last_updated: Time.now.utc)
    write_log(nil, 'synced', "Synced #{synced} templates from Meta for inbox ##{inbox.id}")
    { success: true, synced: synced }
  rescue StandardError => e
    Rails.logger.error "[WA Templates] sync_inbox failed: #{e.message}"
    { success: false, error: e.message }
  end

  def create(inbox, params)
    channel = inbox.channel
    return { success: false, error: 'Not a WhatsApp Cloud inbox' } unless cloud_channel?(channel)

    components = build_components(params)
    body = {
      name: sanitize_name(params[:name]),
      category: params[:category].to_s.upcase,
      language: params[:language] || 'es',
      components: components
    }

    response = HTTParty.post(
      "#{business_path(channel)}/message_templates",
      headers: api_headers(channel),
      body: body.to_json
    )

    return { success: false, error: meta_error(response) } unless response.success?

    meta_id = response['id']
    template = @account.jabvox_whatsapp_templates.create!(
      inbox: inbox,
      meta_template_id: meta_id,
      waba_id: channel.provider_config['business_account_id'],
      phone_number_id: channel.provider_config['phone_number_id'],
      name: body[:name],
      language: body[:language],
      category: body[:category],
      status: response['status'] || 'PENDING',
      body_content: params[:body],
      header_type: params[:header_type],
      header_content: params[:header_content],
      footer_content: params[:footer],
      buttons_json: params[:buttons] || [],
      variables_json: extract_variables(params[:body]),
      meta_json: response.parsed_response || {},
      created_by: @user
    )
    save_version(template)
    write_log(template, 'created', "Template '#{template.name}' created and sent to Meta")
    { success: true, template: template }
  rescue ActiveRecord::RecordInvalid => e
    { success: false, error: e.message }
  rescue StandardError => e
    Rails.logger.error "[WA Templates] create failed: #{e.message}"
    { success: false, error: e.message }
  end

  def update(template, params)
    channel = template.inbox&.channel
    return { success: false, error: 'Not a WhatsApp Cloud inbox' } unless cloud_channel?(channel)

    components = build_components(params)
    body = { components: components }

    response = HTTParty.post(
      "#{business_path(channel)}/message_templates",
      headers: api_headers(channel),
      body: body.merge(id: template.meta_template_id).to_json
    )

    return { success: false, error: meta_error(response) } unless response.success?

    template.update!(
      body_content: params[:body] || template.body_content,
      header_type: params[:header_type] || template.header_type,
      header_content: params[:header_content] || template.header_content,
      footer_content: params[:footer] || template.footer_content,
      buttons_json: params[:buttons] || template.buttons_json,
      variables_json: extract_variables(params[:body] || template.body_content),
      status: 'PENDING'
    )
    save_version(template)
    write_log(template, 'updated', "Template '#{template.name}' updated and resubmitted to Meta")
    { success: true, template: template }
  rescue StandardError => e
    { success: false, error: e.message }
  end

  # NOTE: deleting templates from Jabvox is intentionally not supported — templates are managed
  # at Meta and must be deleted there. Jabvox only mirrors them; removing a WhatsApp inbox
  # cascades away its local copies (see the FK on_delete: :cascade migration).

  def duplicate(template, new_name: nil)
    dup = @account.jabvox_whatsapp_templates.create!(
      inbox: template.inbox,
      waba_id: template.waba_id,
      phone_number_id: template.phone_number_id,
      name: new_name || "#{template.name}_copy",
      language: template.language,
      category: template.category,
      status: 'PENDING',
      header_type: template.header_type,
      header_content: template.header_content,
      body_content: template.body_content,
      footer_content: template.footer_content,
      buttons_json: template.buttons_json,
      variables_json: template.variables_json,
      meta_json: {},
      created_by: @user
    )
    save_version(dup)
    write_log(dup, 'duplicated', "Duplicated from template ##{template.id} '#{template.name}'")
    { success: true, template: dup }
  rescue ActiveRecord::RecordInvalid => e
    { success: false, error: e.message }
  end

  def sync_single(template)
    channel = template.inbox&.channel
    return { success: false, error: 'Not a Cloud API channel' } unless cloud_channel?(channel)

    query = { name: template.name, access_token: channel.provider_config['api_key'] }
    response = HTTParty.get(
      "#{business_path(channel)}/message_templates",
      headers: api_headers(channel), query: query
    )
    return { success: false, error: 'Meta request failed' } unless response.success?

    list = Array(response.parsed_response&.dig('data'))
    # A name can exist in several languages; pick the one matching this template.
    data = list.find { |d| d['language'] == template.language } || list.first
    return { success: false, error: 'Not found in Meta' } unless data

    template.update!(
      status: data['status'] || template.status,
      quality_score: data.dig('quality_score', 'score') || template.quality_score,
      rejected_reason: data['rejected_reason'],
      meta_json: data
    )
    write_log(template, 'synced', "Synced status from Meta: #{data['status']}")
    { success: true, template: template }
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def restore_version(template, version_id)
    ver = template.versions.find(version_id)
    p = ver.payload
    template.update!(
      header_type: p['header_type'], header_content: p['header_content'],
      body_content: p['body_content'], footer_content: p['footer_content'],
      buttons_json: p['buttons_json'] || [], variables_json: p['variables_json'] || {},
      status: 'PENDING'
    )
    save_version(template)
    write_log(template, 'restored', "Restored to version #{ver.version}")
    { success: true, template: template }
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def export_json(inbox_id: nil)
    scope = @account.jabvox_whatsapp_templates
    scope = scope.where(inbox_id: inbox_id) if inbox_id.present?
    scope.map(&:meta_json)
  end

  def export_csv(inbox_id: nil)
    scope = @account.jabvox_whatsapp_templates
    scope = scope.where(inbox_id: inbox_id) if inbox_id.present?
    CSV.generate(headers: true) do |csv|
      csv << %w[id name language category status quality header_type body footer created_at]
      scope.find_each do |t|
        csv << [t.id, t.name, t.language, t.category, t.status, t.quality_score,
                t.header_type, t.body_content, t.footer_content, t.created_at]
      end
    end
  end

  def import_json(inbox, raw_array)
    imported = 0
    errors = []
    Array(raw_array).each_with_index do |raw, i|
      upsert_from_meta(raw, inbox)
      imported += 1
    rescue StandardError => e
      errors << "Row #{i + 1}: #{e.message}"
    end
    write_log(nil, 'synced', "Imported #{imported} templates via JSON")
    { success: true, imported: imported, errors: errors }
  end

  private

  # Fields we explicitly request so Meta returns everything we persist (by default the API
  # omits several of these). Cap at Meta's max page size and follow paging.next.
  META_TEMPLATE_FIELDS = 'id,name,language,category,status,quality_score,components,rejected_reason'.freeze

  def fetch_all_from_meta(channel, url = nil)
    if url.nil?
      url = "#{business_path(channel)}/message_templates"
      query = { fields: META_TEMPLATE_FIELDS, limit: 200, access_token: channel.provider_config['api_key'] }
      response = HTTParty.get(url, headers: api_headers(channel), query: query)
    else
      # paging.next is a fully-formed URL (already includes fields/limit/token).
      response = HTTParty.get(url, headers: api_headers(channel))
    end
    return [] unless response.success?

    data = response.parsed_response['data'] || []
    nxt = response.parsed_response.dig('paging', 'next')
    nxt.present? ? data + fetch_all_from_meta(channel, nxt) : data
  end

  def upsert_from_meta(raw, inbox)
    channel = inbox.channel
    components = raw['components'] || []
    header = components.find { |c| c['type'] == 'HEADER' }
    body_c = components.find { |c| c['type'] == 'BODY' }
    footer_c = components.find { |c| c['type'] == 'FOOTER' }
    buttons_c = components.find { |c| c['type'] == 'BUTTONS' }

    attrs = {
      inbox: inbox,
      meta_template_id: raw['id'],
      waba_id: channel.provider_config['business_account_id'],
      phone_number_id: channel.provider_config['phone_number_id'],
      language: raw['language'],
      category: normalize_category(raw['category']),
      status: normalize_status(raw['status']),
      quality_score: raw.dig('quality_score', 'score'),
      rejected_reason: raw['rejected_reason'],
      header_type: header&.dig('format'),
      header_content: header_content_from(header),
      body_content: body_c&.dig('text'),
      footer_content: footer_c&.dig('text'),
      buttons_json: buttons_c&.dig('buttons') || [],
      variables_json: extract_variables(body_c&.dig('text') || ''),
      meta_json: raw
    }

    existing = @account.jabvox_whatsapp_templates.find_by(
      inbox_id: inbox.id, name: raw['name'], language: raw['language']
    )
    if existing
      existing.update!(attrs)
    else
      @account.jabvox_whatsapp_templates.create!(attrs.merge(name: raw['name']))
    end
  end

  # Builds the components array in the exact shape the WhatsApp Cloud API expects. Meta rejects
  # a template unless every placeholder has a matching example:
  #   - BODY   with {{n}} -> example.body_text = [[v1, v2, ...]]
  #   - HEADER TEXT with {{1}} -> example.header_text = [v1]
  #   - HEADER media (IMAGE/VIDEO/DOCUMENT) -> example.header_handle = [sample_url]
  #   - BUTTON URL with {{1}} -> button.example = [v1]
  # See developers.facebook.com/docs/whatsapp/business-management-api/message-templates.
  def build_components(params)
    components = []
    header = build_header_component(params)
    components << header if header
    body = build_body_component(params[:body])
    components << body if body
    components << { type: 'FOOTER', text: params[:footer] } if params[:footer].present?
    buttons = build_buttons_component(params[:buttons])
    components << buttons if buttons
    components
  end

  def build_header_component(params)
    type = params[:header_type]
    return nil if type.blank? || type == 'NONE'

    if type == 'TEXT'
      # A TEXT header MUST carry text; without it Meta rejects with "Invalid
      # parameter", so we simply omit the header instead of sending it empty.
      text = params[:header_content].to_s
      return nil if text.blank?

      h = { type: 'HEADER', format: 'TEXT', text: text }
      vars = placeholders(text)
      # Header text supports a single {{1}} variable; provide one sample if present.
      h[:example] = { header_text: [sample_value(vars.first)] } if vars.any?
      h
    elsif params[:header_content].present?
      # Media headers need a sample media URL (or uploaded media handle) for approval.
      { type: 'HEADER', format: type, example: { header_handle: [params[:header_content]] } }
    end
  end

  def build_body_component(text)
    return nil if text.blank?

    body = { type: 'BODY', text: text }
    vars = placeholders(text)
    # Meta requires one example value per {{n}} in the body, as a single-row matrix.
    body[:example] = { body_text: [vars.map { |n| sample_value(n) }] } if vars.any?
    body
  end

  def build_buttons_component(buttons)
    list = Array(buttons).select { |b| (b[:text] || b['text']).to_s.present? }
    return nil if list.empty?

    {
      type: 'BUTTONS',
      buttons: list.map do |b|
        type = (b[:type] || b['type']).to_s
        btn = { type: type, text: b[:text] || b['text'] }
        if type == 'URL'
          url = (b[:url] || b['url']).to_s
          btn[:url] = url
          # A dynamic URL ({{1}}) requires an example value.
          btn[:example] = [sample_value(placeholders(url).first)] if placeholders(url).any?
        elsif type == 'PHONE_NUMBER'
          btn[:phone_number] = b[:phone_number] || b['phone_number']
        end
        btn
      end
    }
  end

  # Ordered, unique {{n}} placeholder numbers found in a piece of text.
  def placeholders(text)
    text.to_s.scan(/\{\{\s*(\d+)\s*\}\}/).flatten.map(&:to_i).uniq.sort
  end

  # A harmless sample value Meta accepts for placeholder {{n}} during approval.
  def sample_value(_n)
    'ejemplo'
  end

  def extract_variables(text)
    placeholders(text).each_with_object({}) { |n, h| h[n.to_s] = '' }
  end

  def sanitize_name(name)
    name.to_s.downcase.gsub(/[^a-z0-9_]/, '_').squeeze('_').gsub(/\A_+|_+\z/, '')
  end

  # Builds the clearest possible error string from a failed Meta response,
  # preferring the human-readable fields Meta returns (error_user_title/msg,
  # error_data.details) over the generic "Invalid parameter".
  def meta_error(response)
    err = response.parsed_response&.dig('error') || {}
    parts = [
      err['error_user_title'],
      err['error_user_msg'],
      err.dig('error_data', 'details'),
      err['message']
    ].compact.uniq
    parts.any? ? parts.join(' — ') : (response.body.presence || 'Meta request failed')
  end

  # Meta may return categories/statuses outside our enum (legacy values like SERVICE, or new
  # ones). Map them to the closest allowed value so a sync never fails the model validation.
  def normalize_category(value)
    v = value.to_s.upcase
    JabvoxWhatsappTemplate::CATEGORIES.include?(v) ? v : 'UTILITY'
  end

  def normalize_status(value)
    v = value.to_s.upcase
    JabvoxWhatsappTemplate::STATUSES.include?(v) ? v : 'PENDING'
  end

  # For a media header Meta returns the sample under example.header_handle, not text.
  def header_content_from(header)
    return nil if header.nil?
    return header['text'] if header['format'] == 'TEXT'

    Array(header.dig('example', 'header_handle')).first
  end

  def save_version(template)
    next_ver = (template.versions.maximum(:version) || 0) + 1
    template.versions.create!(
      version: next_ver,
      payload: template.snapshot_payload,
      created_by: @user
    )
  end

  def write_log(template, action, description)
    return unless template

    @account.jabvox_whatsapp_template_logs.create!(
      jabvox_whatsapp_template: template,
      action: action,
      description: description,
      user: @user
    )
  rescue StandardError => e
    Rails.logger.error "[WA Templates] log failed: #{e.message}"
  end

  def cloud_channel?(channel)
    channel.is_a?(Channel::Whatsapp) && channel.provider == 'whatsapp_cloud'
  end

  def whatsapp_cloud_inboxes
    @account.inboxes
            .joins("INNER JOIN channel_whatsapp ON inboxes.channel_id = channel_whatsapp.id " \
                   "AND inboxes.channel_type = 'Channel::Whatsapp'")
            .where("channel_whatsapp.provider = 'whatsapp_cloud'")
  end

  def fresh?(channel)
    ts = channel.message_templates_last_updated
    ts.present? && ts > STALE_AFTER.ago
  end

  def api_version
    ENV.fetch('WHATSAPP_API_VERSION', DEFAULT_API_VERSION)
  end

  def business_path(channel)
    "#{api_base}/#{api_version}/#{channel.provider_config['business_account_id']}"
  end

  def api_headers(channel)
    {
      'Authorization' => "Bearer #{channel.provider_config['api_key']}",
      'Content-Type' => 'application/json'
    }
  end

  def api_base
    ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
  end
end
