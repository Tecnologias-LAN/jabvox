# frozen_string_literal: true

# Evaluador de condiciones COMPARTIDO por `logic.if` y `logic.switch`. Única
# fuente de verdad de los operadores. NUNCA lanza: un operador desconocido o una
# regex inválida devuelven false.
module Jabvox::Flows::Engine::Condition
  OPERATORS = [
    { value: 'equals', label: 'es igual a' },
    { value: 'not_equals', label: 'no es igual a' },
    { value: 'contains', label: 'contiene' },
    { value: 'not_contains', label: 'no contiene' },
    { value: 'starts_with', label: 'empieza por' },
    { value: 'ends_with', label: 'termina en' },
    { value: 'greater_than', label: 'es mayor que' },
    { value: 'greater_or_equal', label: 'es mayor o igual que' },
    { value: 'less_than', label: 'es menor que' },
    { value: 'less_or_equal', label: 'es menor o igual que' },
    { value: 'is_empty', label: 'está vacío', unary: true },
    { value: 'is_not_empty', label: 'no está vacío', unary: true },
    { value: 'regex', label: 'coincide con expresión regular' },
    { value: 'in_list', label: 'está en la lista (separada por comas)' },
    { value: 'not_in_list', label: 'no está en la lista (separada por comas)' },
    { value: 'is_true', label: 'es verdadero', unary: true },
    { value: 'is_false', label: 'es falso', unary: true },
    { value: 'date_equals', label: 'fecha igual a' },
    { value: 'date_before', label: 'fecha anterior a' },
    { value: 'date_after', label: 'fecha posterior a' }
  ].freeze

  # Alias heredados (v2) → operador v3, para flujos ya guardados.
  LEGACY_ALIASES = {
    '==' => 'equals', '===' => 'equals', '!=' => 'not_equals', '!==' => 'not_equals',
    '>' => 'greater_than', '>=' => 'greater_or_equal', '<' => 'less_than', '<=' => 'less_or_equal',
    'startswith' => 'starts_with', 'endswith' => 'ends_with', 'isempty' => 'is_empty',
    'isnotempty' => 'is_not_empty', 'notcontains' => 'not_contains', 'inlist' => 'in_list',
    'notinlist' => 'not_in_list', 'istrue' => 'is_true', 'isfalse' => 'is_false'
  }.freeze

  TRUTHY = %w[true 1 si sí yes on].freeze
  FALSY = %w[false 0 no off].freeze

  module_function

  def normalize_operator(operator)
    raw = operator.to_s.strip
    LEGACY_ALIASES[raw] || LEGACY_ALIASES[raw.downcase] || raw.downcase
  end

  def unary?(operator)
    operator = normalize_operator(operator)
    OPERATORS.any? { |o| o[:value] == operator && o[:unary] }
  end

  # Texto normalizado: trim + minúsculas.
  def text(value)
    case value
    when nil then ''
    when Hash, Array then value.to_json
    else value.to_s.strip.downcase
    end
  end

  # Texto sin bajar a minúsculas (para regex, que sí distingue).
  def raw_text(value)
    case value
    when nil then ''
    when Hash, Array then value.to_json
    else value.to_s.strip
    end
  end

  # Número finito, o nil si el valor no es numérico.
  def numeric(value)
    return nil if value.nil? || value == true || value == false
    return value if value.is_a?(Numeric)

    s = value.to_s.strip
    return nil if s.empty?

    Float(s)
  rescue ArgumentError, TypeError
    nil
  end

  # Instante, o nil si no es una fecha parseable.
  def date_ms(value)
    return nil if value.nil? || value == ''

    temporal = temporal_to_f(value)
    return temporal unless temporal.nil?

    number = numeric(value)
    # Un número suelto se interpreta como epoch (ms si es grande, s si no).
    return epoch_to_f(number) if number && !value.is_a?(String)

    parse_time(value.to_s.strip)
  end

  def temporal_to_f(value)
    return value.to_f if value.is_a?(Time) || value.is_a?(DateTime)
    return value.to_time.to_f if value.is_a?(Date)

    nil
  end

  def epoch_to_f(number)
    number > 1e11 ? number / 1000.0 : number.to_f
  end

  def parse_time(str)
    Time.zone.parse(str)&.to_f
  rescue ArgumentError, TypeError
    nil
  end

  def empty_value?(value)
    case value
    when nil then true
    when String then value.strip == ''
    when Array, Hash then value.empty?
    else false
    end
  end

  def truthy?(value)
    return value if value == true || value == false

    TRUTHY.include?(text(value))
  end

  def falsy?(value)
    return !value if value == true || value == false

    t = text(value)
    FALSY.include?(t) || t == ''
  end

  def to_list(value)
    return value.map { |v| text(v) }.reject(&:empty?) if value.is_a?(Array)

    raw_text(value).split(',').map { |v| text(v) }.reject(&:empty?)
  end

  # Compara dos valores. Nunca lanza: ante cualquier problema devuelve false.
  def evaluate(left, operator, right = nil)
    operator = normalize_operator(operator)
    unary = evaluate_unary(left, operator)
    return unary unless unary.nil?

    ln = numeric(left)
    rn = numeric(right)
    evaluate_equality(left, right, operator, ln, rn) ||
      evaluate_text(left, right, operator) ||
      evaluate_order(left, right, operator, ln, rn) ||
      evaluate_special(left, right, operator) || false
  end

  def evaluate_unary(left, operator)
    case operator
    when 'is_empty' then empty_value?(left)
    when 'is_not_empty' then !empty_value?(left)
    when 'is_true' then truthy?(left)
    when 'is_false' then falsy?(left)
    end
  end

  def evaluate_equality(left, right, operator, l_num, r_num)
    both = !l_num.nil? && !r_num.nil?
    case operator
    when 'equals' then both ? l_num == r_num : text(left) == text(right)
    when 'not_equals' then both ? l_num != r_num : text(left) != text(right)
    end
  end

  def evaluate_text(left, right, operator)
    case operator
    when 'contains' then text(right) != '' && text(left).include?(text(right))
    when 'not_contains' then text(right) == '' || text(left).exclude?(text(right))
    when 'starts_with' then text(right) != '' && text(left).start_with?(text(right))
    when 'ends_with' then text(right) != '' && text(left).end_with?(text(right))
    end
  end

  # Operadores de ORDEN. Si el lado DERECHO (lo que configura el usuario) es
  # numérico, la intención es una comparación NUMÉRICA: un izquierdo no numérico
  # NO puede satisfacerla y da false.
  #
  # BUG QUE ESTO CORRIGE: al caer a texto en cuanto un lado no era numérico,
  # 'telegram' > '1000' era TRUE lexicográficamente, así que un caso de switch
  # { value: "1000", operator: "greater_than" } capturaba CUALQUIER texto y
  # dejaba inalcanzables los casos siguientes y el `default`.
  def evaluate_order(left, right, operator, l_num, r_num)
    return nil unless %w[greater_than greater_or_equal less_than less_or_equal].include?(operator)

    both = !l_num.nil? && !r_num.nil?
    # Texto SOLO cuando ninguno de los dos lados es numérico (ordenar códigos).
    return false unless both || (l_num.nil? && r_num.nil?)

    a = both ? l_num : text(left)
    b = both ? r_num : text(right)
    compare_order(a, b, operator)
  end

  def compare_order(left, right, operator)
    case operator
    when 'greater_than' then left > right
    when 'greater_or_equal' then left >= right
    when 'less_than' then left < right
    when 'less_or_equal' then left <= right
    end
  end

  def evaluate_special(left, right, operator)
    case operator
    when 'regex' then match_regex(left, right)
    when 'in_list' then to_list(right).include?(text(left))
    when 'not_in_list' then to_list(right).exclude?(text(left))
    when 'date_equals', 'date_before', 'date_after' then compare_dates(left, right, operator)
    end
  end

  def match_regex(left, right)
    pattern = raw_text(right)
    return false if pattern == ''

    # Regex inválida → false, jamás una excepción que tumbe el motor.
    Regexp.new(pattern, Regexp::IGNORECASE).match?(raw_text(left))
  rescue RegexpError
    false
  end

  def compare_dates(left, right, operator)
    a = date_ms(left)
    b = date_ms(right)
    return false if a.nil? || b.nil?

    case operator
    when 'date_equals' then a == b
    when 'date_before' then a < b
    when 'date_after' then a > b
    end
  end
end
