# frozen_string_literal: true

# Estructura de una plantilla de WhatsApp: ÚNICA autoridad que deduce qué puntos
# variables tiene, para que el selector y el envío no puedan discrepar (era el
# fallo: el selector decía "2 variables" y el envío exigía otra cosa).
module Jabvox::Flows::Nodes::WhatsappTemplateStructure
  PLACEHOLDER_RE = /\{\{\s*(\d+)\s*\}\}/
  MEDIA_NAMES = { 'image' => 'imagen', 'video' => 'vídeo', 'document' => 'documento' }.freeze

  Parts = Jabvox::Flows::Nodes::WhatsappTemplateParts

  module_function

  # Números de los marcadores `{{n}}` distintos, en orden ascendente.
  def extract_placeholders(text)
    text.to_s.scan(PLACEHOLDER_RE).flatten.uniq.sort_by(&:to_i)
  end

  # Deduce la estructura desde el registro de plantilla del fork.
  def parse(tpl)
    raw = normalize(tpl)
    components = raw['components'].is_a?(Array) ? raw['components'] : []
    body = raw['body_content'].to_s.presence || raw['body'].to_s
    header = Parts.header(raw, components)
    buttons = Parts.buttons(raw, components)
    placeholders = Parts.body_placeholders(body, raw, components)
    parts = { body: body, placeholders: placeholders, header: header, buttons: buttons,
              slots: build_slots(placeholders, header, buttons) }

    describe(raw, components, parts)
  end

  def describe(raw, components, parts)
    header = parts[:header]
    { 'name' => raw['name'].to_s, 'language' => raw['language'].to_s.presence || 'es',
      'category' => raw['category'].to_s.presence || 'UTILITY', 'status' => raw['status'].to_s,
      'bodyContent' => parts[:body], 'bodyPlaceholders' => parts[:placeholders],
      'headerType' => header[:type], 'headerText' => header[:text],
      'headerHasVariable' => header[:has_variable], 'footerText' => Parts.footer(raw, components),
      'buttons' => parts[:buttons], 'slots' => parts[:slots],
      'variableCount' => parts[:placeholders].length, 'requiredSlotCount' => parts[:slots].length }
  end

  # Acepta el modelo del fork o un hash suelto (los flujos importados traen lo
  # segundo, y las pruebas también).
  def normalize(tpl)
    return tpl.deep_stringify_keys if tpl.is_a?(Hash)
    return {} unless tpl.respond_to?(:body_content)

    { 'name' => tpl.name, 'language' => tpl.language, 'category' => tpl.category,
      'status' => tpl.status, 'body_content' => tpl.body_content,
      'header_type' => tpl.header_type, 'header_content' => tpl.header_content,
      'footer_content' => tpl.footer_content, 'buttons' => tpl.buttons_json,
      'variables_json' => tpl.variables_json, 'components' => tpl.meta_json['components'] }
  end

  # TODOS los huecos a rellenar en orden de presentación: cabecera, cuerpo y
  # botones. Es lo que se ve de arriba abajo en el mensaje.
  def build_slots(placeholders, header, buttons)
    slots = header_slots(header)
    placeholders.each do |n|
      slots << { 'key' => n, 'scope' => 'body', 'label' => "Variable {{#{n}}} del mensaje",
                 'expects' => 'text', 'required' => true }
    end
    buttons.each { |b| slots.concat(button_slots(b)) }
    slots
  end

  def header_slots(header)
    return [text_header_slot] if header[:type] == 'text' && header[:has_variable]
    return [] unless MEDIA_NAMES.key?(header[:type])

    [media_header_slot(header[:type])]
  end

  def text_header_slot
    { 'key' => 'header_text', 'scope' => 'header', 'label' => 'Texto de la cabecera',
      'expects' => 'text', 'required' => true,
      'help' => 'Valor que sustituye el hueco de la cabecera.' }
  end

  def media_header_slot(type)
    kind = MEDIA_NAMES[type]
    { 'key' => 'header_media', 'scope' => 'header', 'label' => "URL de la #{kind} de cabecera",
      'expects' => 'media_url', 'required' => true,
      'help' => "Esta plantilla lleva #{kind} en la cabecera: es OBLIGATORIO indicar una URL " \
                'pública (https://…) accesible por Meta.' }
  end

  def button_slots(button)
    name = button['text'].presence || (button['index'] + 1)
    slots = button['dynamicUrl'] ? [url_slot(button, name)] : []
    slots << payload_slot(button, name) if button['hasPayload']
    # Un botón COPY_CODE necesita el cupón a entregar; el FLOW no pide nada al
    # usuario (su flow_token se genera en cada envío).
    slots << copy_code_slot(button, name) if button['type'] == 'copy_code'
    slots
  end

  def copy_code_slot(button, name)
    { 'key' => "button_#{button['index']}_copy_code", 'scope' => 'button',
      'label' => "Código del botón «#{name}»", 'expects' => 'text',
      'required' => true, 'buttonIndex' => button['index'],
      'help' => 'Código que el contacto copia al pulsar el botón (máx. 15 caracteres).' }
  end

  def url_slot(button, name)
    { 'key' => "button_#{button['index']}_url", 'scope' => 'button',
      'label' => "Sufijo de la URL del botón «#{name}»", 'expects' => 'url',
      'required' => true, 'buttonIndex' => button['index'],
      'help' => 'Se añade al final de la URL fija que aprobó Meta.' }
  end

  def payload_slot(button, name)
    { 'key' => "button_#{button['index']}_payload", 'scope' => 'button',
      'label' => "Carga útil del botón «#{name}»", 'expects' => 'payload',
      'required' => true, 'buttonIndex' => button['index'],
      'help' => 'Dato que Jabvox recibe de vuelta cuando el contacto pulsa el botón.' }
  end

  # Huecos que faltan, para que el error diga CUÁNTOS y CUÁLES.
  def missing_slots(structure, values)
    structure['slots'].select do |slot|
      next false unless slot['required']

      value = values[slot['key']].to_s.strip
      # 'text:' a secas es un literal vacío: cuenta como sin rellenar.
      value.empty? || value == 'text:'
    end
  end

  def missing_message(structure, missing)
    detail = missing.map { |s| s['scope'] == 'body' ? "{{#{s['key']}}}" : "«#{s['label']}»" }.join(', ')
    "La plantilla «#{structure['name']}» necesita #{structure['requiredSlotCount']} valor(es) y " \
      "faltan #{missing.length}: #{detail}. Rellénalos en \"Variables de la plantilla\" antes de ejecutar."
  end
end
