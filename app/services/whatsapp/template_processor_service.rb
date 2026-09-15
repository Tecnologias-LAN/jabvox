class Whatsapp::TemplateProcessorService
  pattr_initialize [:channel!, :template_params, :message]

  def call
    return [nil, nil, nil, nil] if template_params.blank?

    process_template_with_params
  end

  # Media del header de la plantilla enviada ({ 'media_url', 'media_type' }) o nil.
  # Lo usa el servicio de envío para adjuntar la imagen a la conversación de Jabvox.
  def resolved_header_media
    return nil if template_params.blank?

    template_media_header(find_template)
  end

  private

  def process_template_with_params
    [
      template_params['name'],
      template_params['namespace'],
      template_params['language'],
      processed_templates_params
    ]
  end

  def find_template
    channel.message_templates.find do |t|
      t['name'] == template_params['name'] &&
        t['language']&.downcase == template_params['language']&.downcase &&
        t['status']&.downcase == 'approved'
    end
  end

  def processed_templates_params
    template = find_template
    return if template.blank?

    # Convert legacy format to enhanced format before processing
    converter = Whatsapp::TemplateParameterConverterService.new(template_params, template)
    normalized_params = converter.normalize_to_enhanced

    process_enhanced_template_params(template, normalized_params['processed_params'])
  end

  def process_enhanced_template_params(template, processed_params = nil)
    processed_params ||= template_params['processed_params']
    components = []

    components.concat(process_header_components(processed_params, template))
    components.concat(process_body_components(processed_params, template))
    components.concat(process_footer_components(processed_params))
    components.concat(process_button_components(processed_params))

    @template_params = components
  end

  def process_header_components(processed_params, template = nil)
    header_data = processed_params['header']
    # Una plantilla con header de media (IMAGE/VIDEO/DOCUMENT) EXIGE el componente header
    # en el envío; si no llega en processed_params, lo tomamos del ejemplo aprobado de la
    # plantilla (la imagen que Meta ya tiene). Sin esto Meta responde "#100 Invalid parameter".
    header_data = template_media_header(template) if header_data.blank?
    return [] if header_data.blank?

    header_params = build_header_params(header_data)
    header_params.present? ? [{ type: 'header', parameters: header_params }] : []
  end

  # Devuelve { media_url, media_type } del ejemplo de media aprobado de la plantilla, o nil.
  def template_media_header(template)
    return nil if template.blank?

    header = Array(template['components']).find { |c| (c['type'] || '').upcase == 'HEADER' }
    return nil if header.blank?

    fmt = (header['format'] || 'TEXT').upcase
    return nil unless %w[IMAGE VIDEO DOCUMENT].include?(fmt)

    handle = header.dig('example', 'header_handle')
    url = handle.is_a?(Array) ? handle.first : handle
    return nil if url.blank?

    { 'media_url' => url, 'media_type' => fmt.downcase }
  end

  def build_header_params(header_data)
    header_params = []
    header_data.each do |key, value|
      next if value.blank?

      if media_url_with_type?(key, header_data)
        media_param = build_media_header_param(value, header_data)
        header_params << media_param if media_param
      elsif key != 'media_type' && key != 'media_name'
        header_params << parameter_builder.build_parameter(value)
      end
    end
    header_params
  end

  # Para header de media: si la URL es la de ejemplo de Meta (scontent/lookaside), no sirve
  # como `link` (Meta la descarga por HTTP/2 y recibe 403 -> "#100"). La resolvemos a un
  # media_id (descarga HTTP/1.1 + subida a /media, cacheado) y usamos { id: media_id }. Si no
  # se puede resolver (o es una URL pública propia), caemos al comportamiento por `link`.
  def build_media_header_param(url, header_data)
    media_type = header_data['media_type']
    media_id = Whatsapp::TemplateMediaResolverService.new(
      channel: channel, media_url: url, media_type: media_type, template_name: template_params['name']
    ).call

    return build_media_id_param(media_id, media_type) if media_id.present?

    parameter_builder.build_media_parameter(url, media_type, header_data['media_name'])
  end

  def build_media_id_param(media_id, media_type)
    { type: media_type.to_s.downcase, media_type.to_s.downcase => { id: media_id } }
  end

  def media_url_with_type?(key, header_data)
    key == 'media_url' && header_data['media_type'].present?
  end

  def process_body_components(processed_params, template)
    return [] if processed_params['body'].blank?

    named = named_format?(template, processed_params['body'])
    # POSITIONAL params are sent as a bare array with no index of their own — Meta
    # matches them to {{1}}, {{2}}... purely by array position. A Ruby Hash keeps
    # insertion order, not numeric order, so a body that arrives as
    # {"2" => "b", "1" => "a"} (JSON from a non-frontend caller, e.g. an API
    # client) would silently swap the values Meta sees. Sort by key numerically
    # before building positional params; NAMED params carry their own
    # parameter_name so order never matters for them.
    ordered_body = named ? processed_params['body'] : sort_positional_body(processed_params['body'])
    body_params = ordered_body.filter_map do |key, value|
      next if value.blank?

      if named
        parameter_builder.build_named_parameter(key, value)
      else
        parameter_builder.build_parameter(value)
      end
    end

    body_params.present? ? [{ type: 'body', parameters: body_params }] : []
  end

  def sort_positional_body(body)
    body.sort_by { |key, _| key.to_s.to_i }
  end

  # ¿La plantilla usa variables NAMED? Meta a veces NO devuelve parameter_format en el
  # payload cacheado, así que lo inferimos también de:
  #   - el ejemplo del BODY (body_text_named_params), o
  #   - el texto del BODY con variables no numéricas ({{nombre}}), o
  #   - las claves de los valores recibidos (no numéricas).
  # Sin esto, un body NAMED se manda sin parameter_name y Meta responde "#100".
  def named_format?(template, body_values)
    return true if template['parameter_format'].to_s.upcase == 'NAMED'
    return false if template['parameter_format'].to_s.upcase == 'POSITIONAL'

    body = Array(template['components']).find { |c| (c['type'] || '').upcase == 'BODY' }
    return true if body && body.dig('example', 'body_text_named_params').present?
    return true if body && body['text'].to_s.scan(/\{\{\s*([^}]+?)\s*\}\}/).flatten.any? { |t| t !~ /\A\d+\z/ }

    Hash(body_values).keys.any? { |k| k.to_s !~ /\A\d+\z/ }
  end

  def process_footer_components(processed_params)
    return [] if processed_params['footer'].blank?

    footer_params = processed_params['footer'].filter_map do |_, value|
      next if value.blank?

      parameter_builder.build_parameter(value)
    end

    footer_params.present? ? [{ type: 'footer', parameters: footer_params }] : []
  end

  # Meta only accepts a button component when the button actually carries a
  # runtime parameter: a URL button with a {{var}}, a COPY_CODE coupon, or a
  # FLOW button (which Meta requires unconditionally, even with no input
  # fields — omitting it triggers "#131009 Components sub_type invalid at
  # index: 0", confirmed against a real send in production and matching
  # Chatwoot's own unresolved flow-support gap, github.com/chatwoot/chatwoot
  # issue #13267). Static QUICK_REPLY buttons (and any other button with no
  # parameter) must NOT emit a component. We keep the button's real index so
  # it maps to the right button.
  def process_button_components(processed_params)
    return [] if processed_params['buttons'].blank?

    button_params = processed_params['buttons'].each_with_index.filter_map do |button, index|
      next if button.blank?
      next unless dynamic_button?(button)

      {
        type: 'button',
        sub_type: button_sub_type(button),
        index: index,
        parameters: [parameter_builder.build_button_parameter(button)]
      }
    end

    button_params.compact
  end

  # A button needs a send-time parameter when it's a COPY_CODE coupon, a FLOW
  # button (always), or a URL button whose value is non-blank (the dynamic URL
  # suffix). Everything else — quick replies, static URLs, phone buttons —
  # carries no parameter.
  def dynamic_button?(button)
    type = button['type'].to_s
    return true if %w[copy_code flow].include?(type)
    return button['parameter'].to_s.strip.present? if type == 'url'

    false
  end

  def button_sub_type(button)
    button['type'].to_s
  end

  def parameter_builder
    @parameter_builder ||= Whatsapp::PopulateTemplateParametersService.new
  end
end
