# frozen_string_literal: true

# Payload de una plantilla para Meta: `processed_params` (huecos del CUERPO) y
# `template_components` (cabecera media y botones dinámicos). Separado del nodo
# porque es traducción de formato, no decisión de envío.
module Jabvox::Flows::Nodes::WhatsappTemplatePayload
  Structure = Jabvox::Flows::Nodes::WhatsappTemplateStructure

  module_function

  # Huecos del CUERPO ({{n}}). Cabecera y botones viajan aparte.
  def body_params(structure, resolved)
    # Sin estructura no se puede distinguir cuerpo de cabecera: se manda todo lo
    # numérico, que es lo único que con seguridad pertenece al cuerpo.
    return resolved.select { |k, _| k.to_s.match?(/\A\d+\z/) } if structure.nil?

    structure['bodyPlaceholders'].index_with { |key| resolved[key].to_s }
  end

  # Componentes de Meta, o nil si la plantilla no lleva ninguno (el caso
  # mayoritario): así no se añade una clave vacía al payload.
  def components(structure, resolved)
    return nil if structure.nil?

    parts = header_component(structure, resolved)
    structure['buttons'].each { |b| parts.concat(button_components(b, resolved)) }
    parts.presence
  end

  def header_component(structure, resolved)
    kind = structure['headerType']
    return [text_header(resolved)] if kind == 'text' && structure['headerHasVariable']
    return [] unless Structure::MEDIA_NAMES.key?(kind)

    [media_header(kind, resolved)]
  end

  def text_header(resolved)
    { 'type' => 'header', 'parameters' => [{ 'type' => 'text', 'text' => resolved['header_text'].to_s }] }
  end

  def media_header(kind, resolved)
    { 'type' => 'header',
      'parameters' => [{ 'type' => kind, kind => { 'link' => resolved['header_media'].to_s } }] }
  end

  def button_components(button, resolved)
    index = button['index']
    return [url_button(index, resolved)] if button['dynamicUrl']
    # Meta exige el componente de un botón FLOW en TODOS los envíos, lleve o no
    # datos iniciales (omitirlo da "#131009 Components sub_type invalid").
    return [flow_button(index)] if button['type'] == 'flow'
    return [copy_code_button(index, resolved)] if button['type'] == 'copy_code'
    return [] unless button['hasPayload']

    [quick_reply_button(index, resolved)]
  end

  # flow_token único por envío: permite correlacionar después la respuesta del
  # Flow con este mensaje concreto.
  def flow_button(index)
    { 'type' => 'button', 'sub_type' => 'flow', 'index' => index,
      'parameters' => [{ 'type' => 'action',
                         'action' => { 'flow_token' => SecureRandom.hex(16), 'flow_action_data' => {} } }] }
  end

  def copy_code_button(index, resolved)
    { 'type' => 'button', 'sub_type' => 'copy_code', 'index' => index,
      'parameters' => [{ 'type' => 'coupon_code',
                         'coupon_code' => resolved["button_#{index}_copy_code"].to_s }] }
  end

  def url_button(index, resolved)
    { 'type' => 'button', 'sub_type' => 'url', 'index' => index,
      'parameters' => [{ 'type' => 'text', 'text' => resolved["button_#{index}_url"].to_s }] }
  end

  def quick_reply_button(index, resolved)
    { 'type' => 'button', 'sub_type' => 'quick_reply', 'index' => index,
      'parameters' => [{ 'type' => 'payload', 'payload' => resolved["button_#{index}_payload"].to_s }] }
  end

  # Cuerpo con las variables ya sustituidas, para que el agente vea en el hilo
  # lo que se envió.
  def rendered_content(structure, template_name, processed)
    body = structure ? structure['bodyContent'].to_s : ''
    return template_name if body.blank?

    body.gsub(Structure::PLACEHOLDER_RE) { processed[Regexp.last_match(1)] || Regexp.last_match(0) }
  end
end
