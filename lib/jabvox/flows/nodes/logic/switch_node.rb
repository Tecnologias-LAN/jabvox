# frozen_string_literal: true

# logic.switch — enruta por el PRIMER caso que casa, o por 'default'. Usa el
# mismo evaluador que logic.if, así que cada caso admite su propio operador.
class Jabvox::Flows::Nodes::Logic::SwitchNode < Jabvox::Flows::Nodes::Base
  type 'logic.switch'
  label 'Enrutar'
  outputs 'default'

  DEFAULT_PORT = 'default'

  def perform
    value = param(:value)
    cases = self.class.parse_cases(param(:cases))
    port_ids = self.class.resolve_port_ids(cases)

    index = cases.index { |c| matches?(value, c) }
    port = index ? port_ids[index] : DEFAULT_PORT
    ok({ 'value' => value, 'matched' => port, 'matchedCase' => index ? cases[index]['value'] : nil,
         'ports' => port_ids + [DEFAULT_PORT] }, output_port: port)
  end

  private

  def matches?(value, kase)
    operator = Jabvox::Flows::Engine::Condition.normalize_operator(first_filled(kase['operator'], 'equals'))
    Jabvox::Flows::Engine::Condition.evaluate(value, operator, kase['value'])
  end

  class << self
    # Acepta array ya parseado o el JSON en texto que guarda el editor. Un
    # `cases` corrupto deja el switch con solo 'default': nunca lanza.
    def parse_cases(raw)
      value = raw
      value = parse_json(value) if value.is_a?(String)
      return [] unless value.is_a?(Array)

      value.filter_map { |c| c.is_a?(Hash) ? c.deep_stringify_keys : nil }
    end

    def parse_json(text)
      trimmed = text.strip
      return [] if trimmed.empty?

      JSON.parse(trimmed)
    rescue JSON::ParserError
      []
    end

    # Id de puerto EFECTIVO por caso: el declarado si es único, o `case<N>`
    # posicional. Dos casos con el mismo puerto dejarían una rama inalcanzable.
    def resolve_port_ids(cases)
      used = Set[DEFAULT_PORT]
      cases.each_with_index.map do |kase, index|
        declared = kase['output'].to_s.strip
        id = declared.present? && used.exclude?(declared) ? declared : unique_positional(used, index)
        used << id
        id
      end
    end

    def unique_positional(used, index)
      n = index + 1
      n += 1 while used.include?("case#{n}")
      "case#{n}"
    end
  end
end
