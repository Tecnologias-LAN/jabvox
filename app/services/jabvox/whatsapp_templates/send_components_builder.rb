# frozen_string_literal: true

# Servicio PURO (sin I/O, sin tocar Message/channel/n8n): arma el array
# `components[]` exacto que Graph API espera en el body de un envío de
# plantilla (`type: 'template', template: { components: [...] } }`), a partir
# de la estructura `components` que la propia plantilla trae de Meta (para
# saber qué tipo de header/botones/carousel/LTO tiene) y de los valores
# concretos a enviar.
#
# Es la ÚNICA pieza que sabe traducir "esta plantilla necesita X" a la forma
# exacta de Meta — los 3 puntos de origen (1:1/Leads/Kanban, Bulk vía n8n,
# Automations) la consumen en vez de reimplementarla cada uno por su lado.
# Ver docs/whatsapp-flows/templates-sending-architecture.md sección 2 para los
# payloads exactos que este servicio reproduce (verificados contra Meta).
#
# Entrada:
#   meta_components: el array `components` tal como Meta lo devuelve para la
#     plantilla (mayúsculas: HEADER/BODY/FOOTER/BUTTONS/CAROUSEL/
#     LIMITED_TIME_OFFER), p.ej. channel.message_templates.find{...}['components']
#     o JabvoxWhatsappTemplate#meta_json['components'].
#   send_params: hash normalizado (claves string o symbol, tolerante) con lo
#     que se quiere enviar:
#     { body_values: {"1"=>"Pablo"} (o NAMED {"nombre"=>"Pablo"}),
#       header: { media_id: | media_url:, media_type: } | { location: {...} },
#       buttons: [{ index:, type: 'flow'|'copy_code'|'url'|'quick_reply'|'voice_call',
#                    parameter:, flow_token:, flow_action_data: }, ...],
#       cards: [{ header: { media_id: | media_url:, media_type: }, buttons: [...] }, ...],
#       auth_code: '123456',
#       location: { latitude:, longitude:, name:, address: },
#       lto_expiration_ms: 1735689600000 }
#
# Salida: Result — success?/components/errors. `components` es el array listo
# para el body de Graph API. Si send_params no trae lo que el tipo de
# plantilla exige, success? es false y errors trae mensajes legibles (mismo
# patrón {success:false, error:} que Jabvox::WhatsappTemplatesManager).
# La clase es larga a propósito: concentra en un solo sitio la forma exacta de
# TODOS los componentes de envío de Meta (header media/location, body
# posicional/NAMED, botones, carousel, OTP, LTO). Repartirla escondería el mapeo
# que este archivo existe para documentar; ver la nota de arquitectura arriba.
class Jabvox::WhatsappTemplates::SendComponentsBuilder # rubocop:disable Metrics/ClassLength
  Result = Struct.new(:success?, :components, :errors) do
    def error
      Array(errors).first
    end
  end

  MEDIA_HEADER_FORMATS = %w[IMAGE VIDEO DOCUMENT].freeze

  def self.call(meta_components:, send_params:)
    new(meta_components: meta_components, send_params: send_params).call
  end

  def initialize(meta_components:, send_params:)
    @meta_components = Array(meta_components).map { |c| indifferent(c) }
    @send_params = indifferent(send_params || {})
    @errors = []
  end

  def call
    components = if authentication_template?
                   build_authentication
                 else
                   build_standard
                 end

    return Result.new(false, nil, @errors) if @errors.any?

    Result.new(true, components.presence || [], [])
  end

  private

  attr_reader :meta_components, :send_params

  # ── Dispatch por tipo de plantilla ──────────────────────────────────────

  def authentication_template?
    otp_button.present?
  end

  def build_standard
    parts = []
    parts.concat(build_header)
    parts.concat(build_body)
    parts.concat(build_buttons)
    parts.concat(build_carousel)
    parts.concat(build_limited_time_offer)
    parts
  end

  # AUTHENTICATION: el código va DOS veces (body {{1}} y botón), mismo valor.
  # Nunca se le pide al usuario texto libre de body — solo el código.
  def build_authentication
    code = send_params[:auth_code].to_s.strip
    if code.blank?
      @errors << 'Falta "auth_code": las plantillas de autenticación necesitan el código a enviar.'
      return []
    end

    [
      { type: 'body', parameters: [{ type: 'text', text: code }] },
      { type: 'button', sub_type: auth_button_sub_type, index: otp_button_index.to_s,
        parameters: [auth_button_parameter(code)] }
    ]
  end

  # sub_type del botón OTP en el ENVÍO: 'url' para ONE_TAP/ZERO_TAP, 'copy_code'
  # para COPY_CODE (la plantilla ya declara cuál es al crearla; aquí solo se lee).
  def auth_button_sub_type
    otp_type = otp_button[:otp_type].to_s.upcase
    otp_type == 'COPY_CODE' ? 'copy_code' : 'url'
  end

  # El mismo código que va en el body viaja en el botón; la clave depende del
  # sub_type (coupon_code para copy_code, text para one-tap/zero-tap).
  def auth_button_parameter(code)
    return { type: 'coupon_code', coupon_code: code } if auth_button_sub_type == 'copy_code'

    { type: 'text', text: code }
  end

  def otp_button
    @otp_button ||= begin
      buttons_component = find_component('BUTTONS')
      btn = Array(buttons_component&.dig(:buttons)).map { |b| indifferent(b) }
                                                   .find { |b| b[:type].to_s.upcase == 'OTP' }
      btn
    end
  end

  def otp_button_index
    buttons_component = find_component('BUTTONS')
    Array(buttons_component&.dig(:buttons)).find_index { |b| indifferent(b)[:type].to_s.upcase == 'OTP' } || 0
  end

  # ── HEADER ───────────────────────────────────────────────────────────────

  def build_header
    header = find_component('HEADER')
    return [] if header.blank?

    format = header[:format].to_s.upcase
    return build_location_header if format == 'LOCATION'
    return build_media_header(format) if MEDIA_HEADER_FORMATS.include?(format)
    return build_text_header if format == 'TEXT'

    []
  end

  def build_location_header
    location = indifferent(send_params[:location])
    if location.blank? || location[:latitude].blank? || location[:longitude].blank?
      @errors << 'Falta "location": el header LOCATION necesita latitude/longitude (y opcionalmente name/address).'
      return []
    end

    [{ type: 'header', parameters: [{ type: 'location', location: {
      latitude: location[:latitude], longitude: location[:longitude],
      name: location[:name].to_s, address: location[:address].to_s
    } }] }]
  end

  def build_media_header(format)
    header_params = send_params[:header]
    media = media_parameter(header_params, format)
    if media.nil?
      @errors << "Falta \"header\": la plantilla tiene un header #{format.downcase} y necesita media_id o media_url."
      return []
    end

    [{ type: 'header', parameters: [media] }]
  end

  # Header TEXT con variable: solo se manda si send_params trae 'header_text'
  # (una plantilla de header de texto SIN variable no exige el componente).
  def build_text_header
    text = send_params[:header_text] || indifferent(send_params[:header])[:text]
    return [] if text.blank?

    [{ type: 'header', parameters: [{ type: 'text', text: text.to_s }] }]
  end

  def media_parameter(header_params, format)
    h = indifferent(header_params)
    return nil if h.blank?

    type = format.downcase
    return { :type => type, type => { id: h[:media_id] } } if h[:media_id].present?
    return { :type => type, type => { link: h[:media_url] } } if h[:media_url].present?

    nil
  end

  # ── BODY ─────────────────────────────────────────────────────────────────

  def build_body
    body_component = find_component('BODY')
    values = indifferent(send_params[:body_values])
    return [] if values.blank?
    # La plantilla no declara BODY (o no se pudo inspeccionar): no se emite el
    # componente aunque lleguen valores sueltos, para no mandar a Meta un
    # parámetro que la plantilla aprobada no tiene.
    return [] if body_component.blank? && meta_components.present?

    params = body_parameters(named_body?(body_component, values), values)
    params.present? ? [{ type: 'body', parameters: params }] : []
  end

  # Los NAMED llevan su parameter_name, así que el orden da igual; los
  # posicionales se ordenan numéricamente porque Meta los empareja con
  # {{1}}, {{2}}… por posición en el array.
  def body_parameters(named, values)
    ordered = named ? values : values.sort_by { |k, _| k.to_s.to_i }
    ordered.filter_map do |key, value|
      next if value.blank?

      named ? { type: 'text', parameter_name: key.to_s, text: value.to_s } : { type: 'text', text: value.to_s }
    end
  end

  def named_body?(body_component, values)
    fmt = body_component && body_component[:text].to_s
    return true if fmt.present? && fmt.scan(/\{\{\s*([^}]+?)\s*\}\}/).flatten.any? { |t| t !~ /\A\d+\z/ }

    values.keys.any? { |k| k.to_s !~ /\A\d+\z/ }
  end

  # ── BUTTONS (FLOW / COPY_CODE / URL dinámico / VOICE_CALL) ────────────────

  def build_buttons
    buttons_component = find_component('BUTTONS')
    declared = Array(buttons_component&.dig(:buttons)).map.with_index { |b, i| [i, indifferent(b)] }
    return [] if declared.empty?

    sent_by_index = Array(send_params[:buttons]).map { |b| indifferent(b) }
                                                .index_by { |b| b[:index].to_i }

    declared.filter_map do |index, declared_button|
      button_component(index, declared_button, sent_by_index[index])
    end
  end

  def button_component(index, declared_button, sent)
    type = declared_button[:type].to_s.upcase

    case type
    when 'FLOW'
      flow_button_component(index, sent)
    when 'COPY_CODE'
      copy_code_button_component(index, sent)
    when 'URL'
      url_button_component(index, sent)
    end
    # QUICK_REPLY estático, PHONE_NUMBER, VOICE_CALL: no llevan parámetro de
    # envío -> no se emite componente (igual que Whatsapp::TemplateProcessorService).
  end

  # Meta exige el componente FLOW SIEMPRE que la plantilla tenga un botón FLOW,
  # incluso sin datos iniciales — omitirlo dispara "#131009".
  def flow_button_component(index, sent)
    flow_token = sent && sent[:flow_token].presence
    flow_action_data = (sent && sent[:flow_action_data].presence) || {}
    { type: 'button', sub_type: 'flow', index: index.to_s,
      parameters: [{ type: 'action', action: { flow_token: flow_token || SecureRandom.hex(16),
                                               flow_action_data: flow_action_data } }] }
  end

  def copy_code_button_component(index, sent)
    code = sent && sent[:parameter].to_s.strip
    if code.blank?
      @errors << "Falta el código de \"buttons[#{index}]\": la plantilla tiene un botón COPY_CODE."
      return nil
    end

    { type: 'button', sub_type: 'copy_code', index: index.to_s,
      parameters: [{ type: 'coupon_code', coupon_code: code }] }
  end

  # Solo se manda si el botón URL de la plantilla es dinámico (tiene sufijo
  # variable) y se proveyó un valor — un URL button estático no lleva parámetro.
  def url_button_component(index, sent)
    value = sent && sent[:parameter].to_s.strip
    return nil if value.blank?

    { type: 'button', sub_type: 'url', index: index.to_s, parameters: [{ type: 'text', text: value }] }
  end

  # ── CAROUSEL ─────────────────────────────────────────────────────────────

  def build_carousel
    carousel_component = find_component('CAROUSEL')
    return [] if carousel_component.blank?

    declared_cards = Array(carousel_component[:cards]).map { |c| indifferent(c) }
    sent_cards = Array(send_params[:cards]).map { |c| indifferent(c) }
    return [] unless carousel_cards_valid?(declared_cards, sent_cards)

    cards = declared_cards.each_with_index.map { |declared_card, i| build_card(i, declared_card, sent_cards[i]) }
    return [] if @errors.any?

    [{ type: 'carousel', cards: cards }]
  end

  def carousel_cards_valid?(declared_cards, sent_cards)
    if sent_cards.empty?
      @errors << 'Falta "cards": la plantilla es un CAROUSEL y necesita al menos una card con sus valores.'
      return false
    end
    if sent_cards.size != declared_cards.size
      @errors << "La plantilla CAROUSEL tiene #{declared_cards.size} card(s) y se enviaron #{sent_cards.size}."
      return false
    end

    true
  end

  def build_card(card_index, declared_card, sent_card)
    components = []
    components.concat(card_header(card_index, declared_card, sent_card))
    components.concat(card_buttons(declared_card, sent_card))
    { card_index: card_index, components: components }
  end

  def card_header(card_index, declared_card, sent_card)
    header = indifferent(declared_card[:components]).presence &&
             Array(declared_card[:components]).map { |c| indifferent(c) }.find { |c| c[:type].to_s.upcase == 'HEADER' }
    return [] if header.blank?

    format = header[:format].to_s.upcase
    media = media_parameter(sent_card[:header], format)
    if media.nil?
      @errors << "Falta el header de la card #{card_index}: necesita media_id o media_url."
      return []
    end

    [{ type: 'header', parameters: [media] }]
  end

  def card_buttons(declared_card, sent_card) # rubocop:disable Metrics/AbcSize
    declared_buttons = Array(declared_card[:components]).map { |c| indifferent(c) }
                                                        .find { |c| c[:type].to_s.upcase == 'BUTTONS' }
    return [] if declared_buttons.blank?

    declared = Array(declared_buttons[:buttons]).map { |b| indifferent(b) }
    sent_by_index = Array(sent_card[:buttons]).map { |b| indifferent(b) }.index_by { |b| b[:index].to_i }

    declared.each_with_index.filter_map do |declared_button, i|
      card_button_component(declared_button[:type].to_s.upcase, i, sent_by_index[i])
    end
  end

  # Dentro de una card Meta solo admite QUICK_REPLY/URL/PHONE_NUMBER; de esos,
  # únicamente los dos primeros llevan parámetro de envío.
  def card_button_component(type, index, sent)
    case type
    when 'QUICK_REPLY' then card_quick_reply_component(index, sent)
    when 'URL' then url_button_component(index, sent)
    end
  end

  def card_quick_reply_component(index, sent)
    return nil if sent.blank? || sent[:parameter].blank?

    { type: 'button', sub_type: 'quick_reply', index: index.to_s,
      parameters: [{ type: 'payload', payload: sent[:parameter].to_s }] }
  end

  # ── LIMITED_TIME_OFFER ──────────────────────────────────────────────────

  def build_limited_time_offer
    lto_component = find_component('LIMITED_TIME_OFFER')
    return [] if lto_component.blank?

    expiration = send_params[:lto_expiration_ms]
    if expiration.blank?
      @errors << 'Falta "lto_expiration_ms": la plantilla tiene LIMITED_TIME_OFFER y necesita la fecha de expiración.'
      return []
    end

    [{ type: 'limited_time_offer', parameters: [{ type: 'limited_time_offer',
                                                  limited_time_offer: { expiration_time_ms: expiration.to_i } }] }]
  end

  # ── helpers ──────────────────────────────────────────────────────────────

  def find_component(type)
    meta_components.find { |c| c[:type].to_s.upcase == type }
  end

  def indifferent(hash)
    return {}.with_indifferent_access if hash.blank?
    return hash.with_indifferent_access if hash.respond_to?(:with_indifferent_access)

    hash
  end
end
