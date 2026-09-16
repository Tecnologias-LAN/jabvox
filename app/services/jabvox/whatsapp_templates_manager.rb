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

    validation_error = validate_params!(params)
    return { success: false, error: validation_error } if validation_error

    components = build_components(params)
    body = {
      name: sanitize_name(params[:name]),
      category: params[:category].to_s.upcase,
      language: params[:language] || 'es',
      components: components
    }
    # Meta necesita saber si las variables son por nombre ({{nombre}}) o por
    # posición ({{1}}). Sin esto, un cuerpo NAMED se rechaza con INVALID_FORMAT.
    body[:parameter_format] = 'NAMED' if named_template?(params[:body], params[:header_content])

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
      template_kind: template_kind_for(params),
      cards_json: params[:cards] || [],
      auth_config_json: params[:auth_config] || {},
      location_header: params[:header_type].to_s.upcase == 'LOCATION',
      limited_time_offer: ActiveModel::Type::Boolean.new.cast(params[:limited_time_offer]) || false,
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

  # Sube un archivo de media a Meta con la Resumable Upload API y devuelve el file
  # handle "h:..." que se usa como example.header_handle al crear/actualizar una
  # plantilla con header IMAGE/VIDEO/DOCUMENT. Meta NO acepta una URL ahí.
  #   uploaded = manager.upload_media(inbox, file_path:, file_type:, file_size:)
  #   uploaded[:handle] => "h:ABC..."
  def upload_media(inbox, file_path:, file_type:, file_size:)
    channel = inbox.channel
    return { success: false, error: 'Not a WhatsApp Cloud inbox' } unless cloud_channel?(channel)

    app_id = whatsapp_app_id(channel)
    if app_id.blank?
      return { success: false,
               error: 'Para subir imágenes o videos a Meta falta configurar el App ID de tu app de Meta ' \
                      '(WHATSAPP_APP_ID en la configuración global del Super Admin, o app_id en la ' \
                      'configuración del canal). Lo encuentras en developers.facebook.com → tu app → Configuración → Básica.' }
    end

    session_id = start_upload_session(channel, app_id, file_size, file_type)
    handle = finish_upload_session(channel, session_id, file_path)
    { success: true, handle: handle }
  rescue StandardError => e
    Rails.logger.error "[WA Templates] upload_media failed: #{e.message}"
    { success: false, error: e.message }
  end

  def update(template, params)
    channel = template.inbox&.channel
    return { success: false, error: 'Not a WhatsApp Cloud inbox' } unless cloud_channel?(channel)

    # merge con lo ya persistido: params llega parcial (solo lo que el form cambió),
    # pero las validaciones de forma (botones, body) necesitan el conjunto completo.
    merged = merged_params_for_validation(template, params)
    validation_error = validate_params!(merged)
    return { success: false, error: validation_error } if validation_error

    components = build_components(merged)
    body = { components: components }
    body[:parameter_format] = 'NAMED' if named_template?(merged[:body], merged[:header_content])

    response = HTTParty.post(
      "#{business_path(channel)}/message_templates",
      headers: api_headers(channel),
      body: body.merge(id: template.meta_template_id).to_json
    )

    return { success: false, error: meta_error(response) } unless response.success?

    template.update!(update_attrs_for(template, params))
    save_version(template)
    write_log(template, 'updated', "Template '#{template.name}' updated and resubmitted to Meta")
    { success: true, template: template }
  rescue StandardError => e
    { success: false, error: e.message }
  end

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def update_attrs_for(template, params)
    {
      body_content: params[:body] || template.body_content,
      header_type: params[:header_type] || template.header_type,
      header_content: params[:header_content] || template.header_content,
      footer_content: params[:footer] || template.footer_content,
      buttons_json: params[:buttons] || template.buttons_json,
      variables_json: extract_variables(params[:body] || template.body_content),
      template_kind: params[:template_kind].presence || template.template_kind,
      cards_json: params[:cards] || template.cards_json,
      auth_config_json: params[:auth_config] || template.auth_config_json,
      location_header: location_header_for(template, params),
      limited_time_offer: limited_time_offer_for(template, params),
      status: 'PENDING'
    }
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  def location_header_for(template, params)
    return template.location_header if params[:header_type].blank?

    params[:header_type].to_s.upcase == 'LOCATION'
  end

  def limited_time_offer_for(template, params)
    return template.limited_time_offer unless params.key?(:limited_time_offer)

    ActiveModel::Type::Boolean.new.cast(params[:limited_time_offer]) || false
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

  # Lee de vuelta templates existentes en Meta -- incluyendo AUTHENTICATION,
  # CAROUSEL, LOCATION header y LIMITED_TIME_OFFER que el usuario pudo haber
  # creado directamente en Meta Business Manager, nunca desde Jabvox. No debe
  # perder datos ni tirar excepción para ninguno de estos; mapea lo que puede a
  # las columnas nuevas y guarda el resto tal cual en meta_json (fuente de verdad).
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  def upsert_from_meta(raw, inbox)
    channel = inbox.channel
    components = raw['components'] || []
    header = components.find { |c| c['type'] == 'HEADER' }
    body_c = components.find { |c| c['type'] == 'BODY' }
    footer_c = components.find { |c| c['type'] == 'FOOTER' }
    buttons_c = components.find { |c| c['type'] == 'BUTTONS' }
    carousel_c = components.find { |c| c['type'] == 'CAROUSEL' }
    lto_c = components.find { |c| c['type'] == 'LIMITED_TIME_OFFER' }

    kind = if carousel_c
             'carousel'
           elsif normalize_category(raw['category']) == 'AUTHENTICATION'
             'authentication'
           else
             'standard'
           end

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
      # AUTHENTICATION no tiene body/footer de texto libre -- Meta genera el
      # texto pero no siempre lo refleja en 'text' al leer; guardamos lo que
      # venga sin asumir su presencia.
      header_content: header_content_from(header),
      body_content: body_c&.dig('text'),
      footer_content: footer_c&.dig('text'),
      buttons_json: buttons_c&.dig('buttons') || [],
      variables_json: extract_variables(body_c&.dig('text') || ''),
      meta_json: raw,
      template_kind: kind,
      cards_json: carousel_c&.dig('cards') || [],
      auth_config_json: kind == 'authentication' ? auth_config_from(body_c, footer_c, buttons_c) : {},
      location_header: header&.dig('format') == 'LOCATION',
      limited_time_offer: lto_c.present?
    }

    existing = @account.jabvox_whatsapp_templates.find_by(
      inbox_id: inbox.id, name: raw['name'], language: raw['language']
    )
    if existing
      existing.update!(attrs)
    else
      @account.jabvox_whatsapp_templates.create!(attrs.merge(name: raw['name']))
    end
  rescue StandardError => e
    # Nunca dejar que un template con una forma inesperada (p.ej. un tipo nuevo
    # de Meta que aún no soportamos) rompa el sync completo del resto de la cuenta.
    Rails.logger.error "[WA Templates] upsert_from_meta failed for '#{raw['name']}': #{e.message}"
    raise
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

  # Reconstruye auth_config_json desde lo que Meta devuelve al leer una
  # plantilla AUTHENTICATION existente (no siempre trae todos los campos).
  # rubocop:disable Metrics/CyclomaticComplexity
  def auth_config_from(body_c, footer_c, buttons_c)
    otp_btn = Array(buttons_c&.dig('buttons')).find { |b| b['type'] == 'OTP' }
    {
      add_security_recommendation: body_c&.dig('add_security_recommendation') || false,
      code_expiration_minutes: footer_c&.dig('code_expiration_minutes'),
      otp_type: otp_btn&.dig('otp_type'),
      supported_apps: otp_btn&.dig('supported_apps') || []
    }.compact
  end
  # rubocop:enable Metrics/CyclomaticComplexity

  # Builds the components array in the exact shape the WhatsApp Cloud API expects. Meta rejects
  # a template unless every placeholder has a matching example:
  #   - BODY   with {{n}} -> example.body_text = [[v1, v2, ...]]
  #   - HEADER TEXT with {{1}} -> example.header_text = [v1]
  #   - HEADER media (IMAGE/VIDEO/DOCUMENT) -> example.header_handle = [sample_url]
  #   - BUTTON URL with {{1}} -> button.example = [v1]
  # See developers.facebook.com/docs/whatsapp/business-management-api/message-templates.
  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def build_components(params)
    kind = template_kind_for(params)
    return build_authentication_components(params) if kind == 'authentication'

    components = []
    header = build_header_component(params)
    components << header if header
    body = build_body_component(params[:body])
    components << body if body
    components << { type: 'FOOTER', text: params[:footer] } if params[:footer].present?
    buttons = build_buttons_component(params[:buttons])
    components << buttons if buttons
    components << build_lto_component if lto?(params)
    components << build_carousel_component(params[:cards]) if kind == 'carousel' && Array(params[:cards]).any?
    components
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # AUTHENTICATION es un modo de formulario distinto, no una variante del mismo:
  # Meta genera el texto de BODY/FOOTER, el formulario libre no aplica. Solo se
  # arma a partir de auth_config (add_security_recommendation, code_expiration_minutes,
  # otp_type, supported_apps) — nunca de header/body/footer libres del form.
  def build_authentication_components(params)
    cfg = (params[:auth_config] || {}).to_h.with_indifferent_access
    components = []
    components << {
      type: 'BODY',
      add_security_recommendation: ActiveModel::Type::Boolean.new.cast(cfg[:add_security_recommendation]) || false
    }
    if cfg[:code_expiration_minutes].present?
      components << {
        type: 'FOOTER',
        code_expiration_minutes: cfg[:code_expiration_minutes].to_i
      }
    end
    components << build_otp_button_component(cfg)
    components
  end

  def build_otp_button_component(cfg)
    otp_type = cfg[:otp_type].presence || 'COPY_CODE'
    btn = { type: 'OTP', otp_type: otp_type }
    if %w[ONE_TAP ZERO_TAP].include?(otp_type)
      apps = Array(cfg[:supported_apps]).map do |a|
        a = a.to_h.with_indifferent_access
        { package_name: a[:package_name], signature_hash: a[:signature_hash] }
      end
      btn[:supported_apps] = apps if apps.any?
    end
    { type: 'BUTTONS', buttons: [btn] }
  end

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  def build_header_component(params)
    type = params[:header_type]
    return nil if type.blank? || type == 'NONE'

    if type == 'LOCATION'
      # Sin example: el contenido (latitude/longitude/name/address) se completa
      # solo al ENVIAR el mensaje de plantilla, nunca al crearla.
      return { type: 'HEADER', format: 'LOCATION' }
    end

    if type == 'TEXT'
      # A TEXT header MUST carry text; without it Meta rejects with "Invalid
      # parameter", so we simply omit the header instead of sending it empty.
      text = params[:header_content].to_s
      return nil if text.blank?

      h = { type: 'HEADER', format: 'TEXT', text: text }
      vars = tokens(text)
      # Header text supports a single variable; provide one sample if present.
      # NAMED usa header_text_named_params; posicional usa header_text.
      if vars.any?
        h[:example] = if named_tokens?(vars)
                        { header_text_named_params: [{ param_name: vars.first, example: sample_value(vars.first) }] }
                      else
                        { header_text: [sample_value(vars.first)] }
                      end
      end
      h
    elsif params[:header_handle].present?
      # Media header (IMAGE/VIDEO/DOCUMENT): Meta exige un file handle "h:..." obtenido con
      # la Resumable Upload API (NO acepta una URL). El handle lo genera #upload_media del
      # controlador (subida previa del archivo) y llega aquí en params[:header_handle].
      { type: 'HEADER', format: type, example: { header_handle: [params[:header_handle]] } }
    end
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

  def build_body_component(text)
    return nil if text.blank?

    body = { type: 'BODY', text: text }
    vars = tokens(text)
    return body if vars.empty?

    # Meta exige un ejemplo por cada variable del cuerpo. El formato depende de si
    # la plantilla es posicional ({{1}}) o NAMED ({{nombre}}):
    #   - posicional: example.body_text = [[v1, v2, ...]]  (matriz de una fila)
    #   - NAMED:      example.body_text_named_params = [{ param_name:, example: }]
    body[:example] = if named_tokens?(vars)
                       { body_text_named_params: vars.map { |t| { param_name: t, example: sample_value(t) } } }
                     else
                       { body_text: [vars.map { |t| sample_value(t) }] }
                     end
    body
  end

  # LIMITED_TIME_OFFER: variante de MARKETING que agrega este componente extra;
  # la fecha de expiración real se completa al enviar, no al crear la plantilla.
  def lto?(params)
    ActiveModel::Type::Boolean.new.cast(params[:limited_time_offer]) &&
      params[:category].to_s.upcase == 'MARKETING'
  end

  def build_lto_component
    { type: 'LIMITED_TIME_OFFER', limited_time_offer: { has_expiration: true } }
  end

  # CAROUSEL: componente adicional de nivel superior con 2-10 cards, cada una su
  # propia mini-plantilla (header IMAGE/VIDEO + hasta 2 botones QUICK_REPLY/URL/
  # PHONE_NUMBER, nunca FLOW/OTP/COPY_CODE dentro de una card).
  def build_carousel_component(cards)
    {
      type: 'CAROUSEL',
      cards: Array(cards).map { |c| build_carousel_card(c.to_h.with_indifferent_access) }
    }
  end

  def build_carousel_card(card)
    components = []
    header_type = card[:header_type].to_s
    if card[:header_handle].present? && %w[IMAGE VIDEO].include?(header_type)
      components << { type: 'HEADER', format: header_type, example: { header_handle: [card[:header_handle]] } }
    end
    body_text = card[:body_content].to_s
    if body_text.present?
      body = { type: 'BODY', text: body_text }
      vars = tokens(body_text)
      body[:example] = { body_text: [vars.map { |t| sample_value(t) }] } if vars.any?
      components << body
    end
    card_buttons = build_buttons_component(card[:buttons])
    components << card_buttons if card_buttons
    { components: components }
  end

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
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
        elsif %w[PHONE_NUMBER VOICE_CALL].include?(type)
          btn[:phone_number] = b[:phone_number] || b['phone_number']
        elsif type == 'COPY_CODE'
          btn[:example] = b[:example] || b['example'] || sample_value(nil)
        elsif type == 'FLOW'
          apply_flow_button!(btn, b)
        end
        btn
      end
    }
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

  # Fills in a FLOW-type template button with the exact shape Meta expects when
  # CREATING a template (architecture doc docs/whatsapp-flows/architecture.md section 2.5):
  #   { type: 'FLOW', text:, flow_id:, flow_action: 'NAVIGATE', navigate_screen: }
  # flow_id here is Meta's OWN id (JabvoxWhatsappFlow#meta_flow_id) resolved by the
  # caller (controller) from the managed Jabvox catalog — never free text. This does not
  # touch the SEND-time payload (Whatsapp::PopulateTemplateParametersService#build_flow_button_parameter),
  # which is a separate, already-implemented mechanic per the architecture doc.
  #
  # flow_action va en MAYÚSCULAS: así lo devuelve Meta en una plantilla aprobada
  # con botón FLOW ("flow_action": "NAVIGATE"), contrastado contra una real.
  def apply_flow_button!(btn, raw)
    flow_id = raw[:flow_id] || raw['flow_id']
    navigate_screen = raw[:navigate_screen] || raw['navigate_screen']
    btn[:flow_id] = flow_id.to_s
    btn[:flow_action] = 'NAVIGATE'
    btn[:navigate_screen] = navigate_screen.to_s if navigate_screen.present?
  end

  # Validación de servidor (autoritativa) ANTES de llamar a Meta. Devuelve un
  # mensaje de error legible (String) si algo no cumple, o nil si todo está bien.
  # El frontend (useTemplateValidation.js) replica estas mismas reglas para dar
  # feedback en vivo, pero el backend nunca confía solo en el cliente.
  # rubocop:disable Metrics/CyclomaticComplexity
  def validate_params!(params)
    kind = template_kind_for(params)
    return validate_authentication_params(params) if kind == 'authentication'

    error = validate_body!(params[:body])
    return error if error

    error = validate_footer!(params[:footer])
    return error if error

    error = validate_header_text!(params) if params[:header_type].to_s.upcase == 'TEXT'
    return error if error

    error = validate_buttons!(params[:buttons])
    return error if error

    return validate_carousel!(params[:cards]) if kind == 'carousel'

    nil
  end
  # rubocop:enable Metrics/CyclomaticComplexity

  # rubocop:disable Metrics/CyclomaticComplexity
  def validate_authentication_params(params)
    cfg = (params[:auth_config] || {}).to_h.with_indifferent_access
    if cfg[:code_expiration_minutes].present?
      minutes = cfg[:code_expiration_minutes].to_i
      return 'code_expiration_minutes debe estar entre 1 y 90.' unless minutes.between?(1, 90)
    end
    otp_type = cfg[:otp_type].presence || 'COPY_CODE'
    return 'otp_type debe ser ONE_TAP, COPY_CODE o ZERO_TAP.' unless %w[ONE_TAP COPY_CODE ZERO_TAP].include?(otp_type)
    if %w[ONE_TAP ZERO_TAP].include?(otp_type) && Array(cfg[:supported_apps]).empty?
      return "otp_type #{otp_type} requiere al menos una app en supported_apps (package_name + signature_hash)."
    end

    nil
  end
  # rubocop:enable Metrics/CyclomaticComplexity

  # BODY: ≤1024 caracteres, sin variable al borde, sin variables consecutivas sin
  # texto entre ellas, sin mezcla posicional+NAMED (bug real: named_tokens? antes
  # trataba todo como NAMED si CUALQUIER variable no era numérica, dejando pasar
  # un body con {{1}} Y {{nombre}} juntos hacia un payload que Meta rechaza tarde).
  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def validate_body!(text)
    return nil if text.blank?

    return "El cuerpo no puede superar 1024 caracteres (tiene #{text.length})." if text.length > 1024

    vars = tokens(text)
    return nil if vars.empty?

    return 'El cuerpo no puede empezar ni terminar con una variable. Agrega texto fijo antes y después.' if edge_variable?(text)

    return 'Dos variables no pueden ir consecutivas sin texto entre ellas.' if consecutive_variables?(text)

    return 'No se pueden mezclar variables posicionales ({{1}}) y con nombre ({{nombre}}) en el mismo cuerpo.' if mixed_variable_types?(vars)

    if !named_tokens?(vars) && !sequential_positionals?(vars)
      return 'Las variables posicionales deben ser secuenciales sin saltos: {{1}}, {{2}}, {{3}}… (no {{1}}, {{3}}).'
    end

    nil
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  def validate_footer!(text)
    return nil if text.blank?

    "El pie de página no puede superar 60 caracteres (tiene #{text.length})." if text.length > 60
  end

  def validate_header_text!(params)
    text = params[:header_content].to_s
    return nil if text.blank?

    "El texto del encabezado no puede superar 60 caracteres (tiene #{text.length})." if text.length > 60
  end

  def edge_variable?(text)
    body = text.to_s.strip
    /\A\{\{[^}]+\}\}/.match?(body) || /\{\{[^}]+\}\}\z/.match?(body)
  end

  # Dos variables consecutivas sin ningún carácter significativo (letra/número)
  # entre ellas -- "{{1}}{{2}}" o "{{1}} {{2}}" (solo un espacio) cuentan como
  # inválidas; Meta exige texto real (una palabra) entre variables.
  def consecutive_variables?(text)
    text.to_s.scan(/\{\{[^}]+\}\}(\s*)\{\{[^}]+\}\}/).any? { |(between)| between.to_s.strip.empty? }
  end

  def mixed_variable_types?(vars)
    numeric = vars.grep(/\A\d+\z/)
    named = vars - numeric
    numeric.any? && named.any?
  end

  def sequential_positionals?(vars)
    nums = vars.map(&:to_i).sort
    nums == (1..nums.size).to_a
  end

  BUTTON_MAX_TOTAL = 10
  BUTTON_TYPE_MAX = {
    'QUICK_REPLY' => 10, 'URL' => 2, 'PHONE_NUMBER' => 1,
    'VOICE_CALL' => 1, 'COPY_CODE' => 1, 'OTP' => 1
  }.freeze

  # Valida ANTES de llamar a Meta: tope 10, límites por tipo, COPY_CODE exclusivo,
  # PHONE_NUMBER/VOICE_CALL mutuamente excluyentes, y agrupación por tipo contiguo.
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def validate_buttons!(buttons)
    list = Array(buttons).select { |b| (b[:text] || b['text']).to_s.present? }
    return nil if list.empty?

    return "Máximo 10 botones combinados (hay #{list.length})." if list.length > BUTTON_MAX_TOTAL

    types = list.map { |b| (b[:type] || b['type']).to_s }

    return 'El botón COPY_CODE no puede combinarse con ningún otro tipo de botón.' if types.include?('COPY_CODE') && types.uniq.length > 1

    return 'Los botones PHONE_NUMBER y VOICE_CALL son mutuamente excluyentes.' if types.include?('PHONE_NUMBER') && types.include?('VOICE_CALL')

    BUTTON_TYPE_MAX.each do |type, max|
      count = types.count(type)
      return "Máximo #{max} botón(es) de tipo #{type} (hay #{count})." if count > max
    end

    return 'Los botones del mismo tipo deben ir agrupados (no intercalados con otros tipos).' unless grouped_by_type?(types)

    nil
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  # El orden es válido si, agrupando por tipo, cada tipo aparece como un bloque
  # contiguo (comparado contra el orden de "primera aparición" de cada tipo).
  def grouped_by_type?(types)
    seen_order = types.uniq
    rebuilt = []
    seen_order.each { |t| rebuilt.concat(types.select { |x| x == t }) }
    # Si reagrupar por tipo produce la MISMA secuencia que la original, ya estaba
    # agrupada; si no, había una intercalación.
    rebuilt == types
  end

  CARD_MIN = 2
  CARD_MAX = 10
  CARD_FORBIDDEN_BUTTON_TYPES = %w[FLOW OTP COPY_CODE].freeze
  CARD_ALLOWED_HEADER_TYPES = %w[IMAGE VIDEO].freeze

  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  def validate_carousel!(cards)
    list = Array(cards)
    return 'Carousel requiere entre 2 y 10 cards.' if list.size < CARD_MIN || list.size > CARD_MAX

    button_signatures = []
    has_body_flags = []
    list.each_with_index do |raw, i|
      card = raw.to_h.with_indifferent_access
      return "Card #{i + 1}: el header debe ser IMAGE o VIDEO." unless CARD_ALLOWED_HEADER_TYPES.include?(card[:header_type].to_s)

      card_buttons = Array(card[:buttons])
      card_buttons.each do |b|
        b = b.to_h.with_indifferent_access
        if CARD_FORBIDDEN_BUTTON_TYPES.include?(b[:type].to_s)
          return "Card #{i + 1}: el tipo de botón #{b[:type]} no está permitido dentro de una card (solo QUICK_REPLY/URL/PHONE_NUMBER)."
        end
      end
      return "Card #{i + 1}: máximo 2 botones." if card_buttons.size > 2

      button_signatures << card_buttons.map { |b| b.to_h.with_indifferent_access[:type] }
      has_body_flags << card[:body_content].to_s.present?
    end

    return 'Si una card tiene body propio, todas las cards deben tenerlo.' if has_body_flags.uniq.size > 1

    return 'Todas las cards deben compartir el mismo conjunto y orden de tipos de botón.' if button_signatures.uniq.size > 1

    nil
  end
  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

  def template_kind_for(params)
    kind = params[:template_kind].presence
    return kind if kind.present? && JabvoxWhatsappTemplate::TEMPLATE_KINDS.include?(kind)
    return 'authentication' if params[:category].to_s.upcase == 'AUTHENTICATION'

    'standard'
  end

  # Al actualizar, params trae solo lo que el usuario cambió; para validar reglas
  # que dependen del conjunto completo (botones, body) se completa con lo ya
  # persistido en el template.
  MERGE_FIELDS = {
    body: :body_content, footer: :footer_content, header_type: :header_type,
    header_content: :header_content, buttons: :buttons_json, cards: :cards_json,
    auth_config: :auth_config_json
  }.freeze

  def merged_params_for_validation(template, params)
    merged = {
      template_kind: params[:template_kind].presence || template.template_kind,
      category: params[:category].presence || template.category
    }
    MERGE_FIELDS.each do |param_key, template_attr|
      merged[param_key] = params.key?(param_key) ? params[param_key] : template.public_send(template_attr)
    end
    merged
  end

  # Ordered, unique {{n}} placeholder numbers found in a piece of text.
  def placeholders(text)
    text.to_s.scan(/\{\{\s*(\d+)\s*\}\}/).flatten.map(&:to_i).uniq.sort
  end

  # TODAS las variables de un texto, posicionales ({{1}}) o NAMED ({{nombre}},
  # {{nombre_empresa}}), en orden de aparición y sin repetir. El token es el
  # contenido entre llaves, recortado. Meta exige un ejemplo por cada uno.
  def tokens(text)
    text.to_s.scan(/\{\{\s*([^}]+?)\s*\}\}/).flatten.uniq
  end

  # La plantilla es NAMED si alguna variable no es puramente numérica. Meta trata
  # todo el conjunto como NAMED o como posicional (no se mezclan).
  def named_tokens?(list)
    Array(list).any? { |t| t.to_s !~ /\A\d+\z/ }
  end

  # ¿El texto usa variables NAMED? (para fijar parameter_format en el payload).
  def named_template?(*texts)
    named_tokens?(texts.compact.flat_map { |t| tokens(t) })
  end

  # A harmless sample value Meta accepts for placeholder {{n}} during approval.
  def sample_value(_placeholder)
    'ejemplo'
  end

  def extract_variables(text)
    # Guarda TODAS las variables (posicionales y NAMED) para la pestaña Variables.
    tokens(text).each_with_object({}) { |t, h| h[t.to_s] = '' }
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
            .joins('INNER JOIN channel_whatsapp ON inboxes.channel_id = channel_whatsapp.id ' \
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

  # App ID de Meta, requerido por la Resumable Upload API. Se busca, en orden:
  # el canal (provider_config), el config global, y por último la fila de
  # InstallationConfig directamente.
  #
  # Ese último paso importa: GlobalConfig cachea en Redis durante un día, así
  # que si el valor se guardó en el Super Admin DESPUÉS de que un nil quedara
  # cacheado, seguiría dando "falta configurar" hasta que expire la caché.
  # Leer la fila evita ese falso negativo.
  def whatsapp_app_id(channel = nil)
    from_channel = channel&.provider_config.to_h['app_id']
    return from_channel if from_channel.present?

    from_global = GlobalConfigService.load('WHATSAPP_APP_ID', '')
    return from_global if from_global.present?

    InstallationConfig.find_by(name: 'WHATSAPP_APP_ID')&.value.presence
  end

  # Paso 1 de la Resumable Upload API: abre una sesión de subida y devuelve su id.
  #   POST /{app_id}/uploads?file_length=&file_type=  (auth por Bearer)
  def start_upload_session(channel, app_id, file_size, file_type)
    resp = HTTParty.post(
      "#{api_base}/#{api_version}/#{app_id}/uploads",
      headers: { 'Authorization' => "Bearer #{channel.provider_config['api_key']}" },
      query: { file_length: file_size, file_type: file_type }
    )
    raise "No se pudo iniciar la subida: #{meta_error(resp)}" unless resp.success? && resp['id'].present?

    resp['id']
  end

  # Paso 2: sube el binario a la sesión. La autorización aquí es "OAuth <token>"
  # (no Bearer) y el body es el archivo crudo. Devuelve el handle "h:...".
  def finish_upload_session(channel, session_id, file_path)
    resp = HTTParty.post(
      "#{api_base}/#{api_version}/#{session_id}",
      headers: {
        'Authorization' => "OAuth #{channel.provider_config['api_key']}",
        'file_offset' => '0',
        'Content-Type' => 'application/octet-stream'
      },
      body: File.binread(file_path)
    )
    raise "No se pudo subir el archivo: #{meta_error(resp)}" unless resp.success? && resp['h'].present?

    resp['h']
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
