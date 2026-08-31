# frozen_string_literal: true

# trigger.jabvox_event — dispara con un evento de Jabvox. El payload del evento
# queda en `{{trigger.*}}`.
class Jabvox::Flows::Nodes::Triggers::JabvoxEventNode
  TYPE = 'trigger.jabvox_event'
  LABEL = 'Evento de Jabvox'
  ANY_EVENT = '*'

  # Eventos que Jabvox emite por webhook de cuenta. No inventar valores: uno que
  # no se emite nunca dispararía el flujo.
  EVENTS = %w[conversation_created conversation_updated conversation_status_changed
              message_created message_updated contact_created contact_updated
              webwidget_triggered].freeze

  def self.register_on(registry)
    registry.register(TYPE, label: LABEL)
  end

  def self.matches?(node, payload = {})
    payload = (payload || {}).deep_stringify_keys
    event_matches?(node, payload) && inbox_matches?(node, payload) && filter_matches?(node, payload)
  end

  def self.event_matches?(node, payload)
    wanted = params_of(node)['event'].to_s.strip
    return true if wanted.blank? || wanted == ANY_EVENT

    wanted == payload['event'].to_s
  end

  # Los eventos SIN bandeja (contacto creado/actualizado) se IGNORAN cuando se
  # filtra por bandeja: no hay forma de saber si son de la que se pidió.
  def self.inbox_matches?(node, payload)
    wanted = params_of(node)['inboxId'].to_s.strip
    return true if wanted.blank?

    actual = payload['inbox_id'] || payload.dig('inbox', 'id') || payload.dig('conversation', 'inbox_id')
    actual.present? && actual.to_s == wanted
  end

  # Igualdades sobre el payload que deben cumplirse TODAS. Las claves admiten
  # rutas con punto y el valor puede ser una lista (OR entre valores).
  def self.filter_matches?(node, payload)
    filter = parse_filter(params_of(node)['filterJson'])
    return true if filter.nil?

    filter.all? do |path, expected|
      actual = Jabvox::Flows::Engine::Template.get_by_path(payload, path)
      # Comparación por texto: los ids llegan number en unos eventos y string
      # en otros, y el JSON del filtro los suele traer en texto.
      Array.wrap(expected).any? { |v| v.to_s == actual.to_s }
    end
  end

  # Un filtro inválido se IGNORA: nunca bloquea el disparo por un error de
  # configuración, pero se registra para poder depurarlo.
  def self.parse_filter(raw)
    value = raw
    value = parse_json(value) if value.is_a?(String)
    return nil unless value.is_a?(Hash) && value.any?

    value
  end

  def self.parse_json(text)
    trimmed = text.strip
    return nil if trimmed.empty?

    JSON.parse(trimmed)
  rescue JSON::ParserError
    Rails.logger.warn('filterJson del trigger jabvox_event no es JSON válido: se ignora.')
    nil
  end

  def self.params_of(node)
    node.respond_to?(:params) && node.params.is_a?(Hash) ? node.params : {}
  end
end
