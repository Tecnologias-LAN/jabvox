require 'httparty'
require 'csv'

class Jabvox::WhatsappTemplatesManager
  WHATSAPP_API_VERSION = 'v14.0'.freeze
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

    unless response.success?
      error_msg = response.parsed_response&.dig('error', 'message') || response.body
      return { success: false, error: error_msg }
    end

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
    channel = template.inbox.channel
    components = build_components(params)
    body = { components: components }

    response = HTTParty.post(
      "#{business_path(channel)}/message_templates",
      headers: api_headers(channel),
      body: body.merge(id: template.meta_template_id).to_json
    )

    unless response.success?
      error_msg = response.parsed_response&.dig('error', 'message') || response.body
      return { success: false, error: error_msg }
    end

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

  def destroy(template)
    channel = template.inbox.channel
    HTTParty.delete(
      "#{business_path(channel)}/message_templates?name=#{template.name}",
      headers: api_headers(channel)
    )
    write_log(template, 'deleted', "Template '#{template.name}' deleted")
    template.destroy!
    { success: true }
  rescue StandardError => e
    { success: false, error: e.message }
  end

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
    channel = template.inbox.channel
    return { success: false, error: 'Not a Cloud API channel' } unless cloud_channel?(channel)

    response = HTTParty.get(
      "#{business_path(channel)}/message_templates?name=#{template.name}",
      headers: api_headers(channel)
    )
    return { success: false, error: 'Meta request failed' } unless response.success?

    data = response.parsed_response&.dig('data')&.first
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

  def fetch_all_from_meta(channel, url = nil)
    url ||= "#{business_path(channel)}/message_templates"
    response = HTTParty.get(url, headers: api_headers(channel))
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
      category: raw['category'] || 'UTILITY',
      status: raw['status'] || 'PENDING',
      quality_score: raw.dig('quality_score', 'score'),
      rejected_reason: raw['rejected_reason'],
      header_type: header&.dig('format'),
      header_content: header&.dig('text'),
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

  def build_components(params)
    components = []
    if params[:header_type].present? && params[:header_type] != 'NONE'
      h = { type: 'HEADER', format: params[:header_type] }
      h[:text] = params[:header_content] if params[:header_type] == 'TEXT'
      components << h
    end
    components << { type: 'BODY', text: params[:body] } if params[:body].present?
    components << { type: 'FOOTER', text: params[:footer] } if params[:footer].present?
    if Array(params[:buttons]).any?
      components << {
        type: 'BUTTONS',
        buttons: params[:buttons].map do |b|
          btn = { type: b[:type] || b['type'], text: b[:text] || b['text'] }
          btn[:url] = b[:url] || b['url'] if btn[:type] == 'URL'
          btn[:phone_number] = b[:phone_number] || b['phone_number'] if btn[:type] == 'PHONE_NUMBER'
          btn
        end
      }
    end
    components
  end

  def extract_variables(text)
    return {} if text.blank?

    vars = text.scan(/\{\{(\d+)\}\}/).flatten.map(&:to_i).uniq.sort
    vars.each_with_object({}) { |n, h| h[n.to_s] = '' }
  end

  def sanitize_name(name)
    name.to_s.downcase.gsub(/[^a-z0-9_]/, '_').squeeze('_').strip
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

  def business_path(channel)
    "#{api_base}/#{WHATSAPP_API_VERSION}/#{channel.provider_config['business_account_id']}"
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
