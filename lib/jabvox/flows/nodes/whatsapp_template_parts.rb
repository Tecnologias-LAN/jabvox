# frozen_string_literal: true

# Partes de una plantilla de WhatsApp: marcadores del cuerpo, cabecera y
# botones. Es TOLERANTE a propósito: los forks exponen esto como campos planos,
# como `components[]` estilo Meta o vía `variables_json`, así que se prueban
# todas las formas conocidas y lo que no venga queda en su valor neutro.
module Jabvox::Flows::Nodes::WhatsappTemplateParts
  module_function

  # Si el cuerpo no trae `{{n}}` se recurre al componente BODY o a
  # `variables_json`: algunos forks guardan el cuerpo ya sustituido pero
  # conservan la lista de variables.
  def body_placeholders(body, raw, components)
    from_body = extract(body)
    return from_body if from_body.any?

    component = find_component(components, 'BODY')
    from_component = extract(str(component&.dig('text') || component&.dig('body')))
    return from_component if from_component.any?

    from_variables(raw['variables_json'] || raw['variables'])
  end

  def from_variables(vars)
    return positional(vars.length) if vars.is_a?(Array)
    return [] unless vars.is_a?(Hash)

    from_variable_keys(vars.keys.map(&:to_s))
  end

  def from_variable_keys(keys)
    return [] if keys.empty?
    # Claves numéricas → son los propios números del marcador.
    return keys.sort_by(&:to_i) if keys.all? { |k| k.match?(/\A\d+\z/) }

    positional(keys.length)
  end

  def positional(count)
    (1..count).map(&:to_s)
  end

  def header(raw, components)
    component = find_component(components, 'HEADER')
    format = str(raw['header_type'] || raw['headerType'] || component&.dig('format')).upcase
    text = str(raw['header_content'] || raw['header_text'] || component&.dig('text'))
    type = header_type(format, text)
    { type: type, text: text, has_variable: type == 'text' && extract(text).any? }
  end

  def header_type(format, text)
    return format.downcase if %w[TEXT IMAGE VIDEO DOCUMENT].include?(format)
    # Sin formato declarado pero con texto: es una cabecera de texto.
    return 'text' if text.present?

    'none'
  end

  def footer(raw, components)
    str(raw['footer_content'] || raw['footer_text'] || find_component(components, 'FOOTER')&.dig('text'))
  end

  def buttons(raw, components)
    source = raw['buttons'].is_a?(Array) ? raw['buttons'] : find_component(components, 'BUTTONS')&.dig('buttons')
    return [] unless source.is_a?(Array)

    source.each_with_index.map { |b, index| button(b.is_a?(Hash) ? b.stringify_keys : {}, index) }
  end

  def button(button, index)
    kind = str(button['type'] || button['button_type']).upcase
    url = str(button['url'])
    text = str(button['text'] || button['label'])
    return url_button(index, text, url) if kind == 'URL' || (kind.empty? && url.present?)
    return quick_reply(button, index, text) if kind == 'QUICK_REPLY'

    plain_button(kind, index, text)
  end

  def plain_button(kind, index, text)
    { 'index' => index, 'type' => kind == 'PHONE_NUMBER' ? 'phone_number' : 'other', 'text' => text }
  end

  # Meta admite un único sufijo dinámico al final de la URL.
  def url_button(index, text, url)
    { 'index' => index, 'type' => 'url', 'text' => text, 'dynamicUrl' => extract(url).any? }
  end

  # La carga útil solo es configurable si el fork la declara editable.
  def quick_reply(button, index, text)
    declares = button.key?('payload') || button.key?('has_payload') || button.key?('hasPayload')
    { 'index' => index, 'type' => 'quick_reply', 'text' => text,
      'hasPayload' => declares && button['has_payload'] != false }
  end

  def find_component(components, type)
    components.find { |c| c.is_a?(Hash) && str(c['type'] || c[:type]).upcase == type }&.stringify_keys
  end

  def extract(text)
    Jabvox::Flows::Nodes::WhatsappTemplateStructure.extract_placeholders(text)
  end

  def str(value)
    value.nil? ? '' : value.to_s
  end
end
