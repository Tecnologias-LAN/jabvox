class Whatsapp::TemplateProcessorService
  pattr_initialize [:channel!, :template_params, :message]

  def call
    return [nil, nil, nil, nil] if template_params.blank?

    process_template_with_params
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
        media_name = header_data['media_name']
        media_param = parameter_builder.build_media_parameter(value, header_data['media_type'], media_name)
        header_params << media_param if media_param
      elsif key != 'media_type' && key != 'media_name'
        header_params << parameter_builder.build_parameter(value)
      end
    end
    header_params
  end

  def media_url_with_type?(key, header_data)
    key == 'media_url' && header_data['media_type'].present?
  end

  def process_body_components(processed_params, template)
    return [] if processed_params['body'].blank?

    named = named_format?(template, processed_params['body'])
    body_params = processed_params['body'].filter_map do |key, value|
      next if value.blank?

      if named
        parameter_builder.build_named_parameter(key, value)
      else
        parameter_builder.build_parameter(value)
      end
    end

    body_params.present? ? [{ type: 'body', parameters: body_params }] : []
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
  # runtime parameter: a URL button with a {{var}}, or a COPY_CODE coupon.
  # Static QUICK_REPLY buttons (and any button with no parameter) must NOT emit
  # a component — sending one triggers Meta error #131009 "Parameter value is
  # not valid". We keep the button's real index so it maps to the right button.
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

  # A button needs a send-time parameter only when it's a COPY_CODE coupon or a
  # URL button whose value is non-blank (the dynamic URL suffix). Everything
  # else — quick replies, static URLs, phone buttons — carries no parameter.
  def dynamic_button?(button)
    type = button['type'].to_s
    return true if type == 'copy_code'
    return button['parameter'].to_s.strip.present? if type == 'url'

    false
  end

  def button_sub_type(button)
    button['type'].to_s == 'copy_code' ? 'copy_code' : 'url'
  end

  def parameter_builder
    @parameter_builder ||= Whatsapp::PopulateTemplateParametersService.new
  end
end
