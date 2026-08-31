# frozen_string_literal: true

# Intérprete de expresiones ACOTADO y SEGURO: NO usa eval ni instance_eval.
# Tokenizador simple + parser de precedencia (Pratt-lite). Cualquier
# construcción no soportada lanza un error controlado.
class Jabvox::Flows::Engine::Expression
  Error = Class.new(StandardError)

  OPERATORS = ['===', '!==', '==', '!=', '>=', '<=', '&&', '||', '>', '<', '+', '-', '*', '/', '%'].freeze

  PRECEDENCE = {
    '||' => 1, '&&' => 2,
    '==' => 3, '!=' => 3, '===' => 3, '!==' => 3, 'contains' => 3,
    '>' => 4, '>=' => 4, '<' => 4, '<=' => 4,
    '+' => 5, '-' => 5,
    '*' => 6, '/' => 6, '%' => 6
  }.freeze

  Token = Struct.new(:type, :value)

  # Evalúa una expresión sobre el contexto de ejecución.
  def self.evaluate(expression, ctx)
    new(expression, Jabvox::Flows::Engine::Template.scope_for(ctx)).evaluate
  end

  def initialize(expression, scope)
    @tokens = self.class.tokenize(expression)
    @scope = scope
    @pos = 0
  end

  def evaluate
    value = parse_expression(0)
    raise Error, 'Expresión mal formada (tokens sobrantes).' if @pos < @tokens.length

    value
  end

  class << self
    def tokenize(input)
      tokens = []
      scanner = StringScanner.new(input.to_s)
      until scanner.eos?
        next if scanner.skip(/\s+/)

        tokens << next_token(scanner)
      end
      tokens
    end

    def next_token(scanner)
      scan_string(scanner) || scan_number(scanner) || scan_paren(scanner) ||
        scan_operator(scanner) || scan_identifier(scanner) ||
        raise(Error, "Carácter no soportado en expresión: '#{scanner.getch}'")
    end

    def scan_string(scanner)
      quote = scanner.scan(/['"]/)
      return nil unless quote

      body = scanner.scan_until(/#{Regexp.escape(quote)}|\z/).to_s.chomp(quote)
      Token.new(:str, body.gsub(/\\(.)/, '\1'))
    end

    def scan_number(scanner)
      num = scanner.scan(/\d[\d.]*|\.\d+/)
      return unless num

      Token.new(:num, num.include?('.') ? num.to_f : num.to_i)
    end

    def scan_paren(scanner)
      return Token.new(:lparen, '(') if scanner.scan('(')

      scanner.scan(')') ? Token.new(:rparen, ')') : nil
    end

    def scan_operator(scanner)
      operator = OPERATORS.find { |o| scanner.match?(/#{Regexp.escape(o)}/) }
      return nil unless operator

      scanner.pos += operator.length
      Token.new(:operator, operator)
    end

    def scan_identifier(scanner)
      id = scanner.scan(/[A-Za-z_][A-Za-z0-9_.\[\]]*/)
      return nil unless id

      id == 'contains' ? Token.new(:operator, 'contains') : Token.new(:ident, id)
    end
  end

  private

  def peek
    @tokens[@pos]
  end

  def parse_expression(min_prec)
    left = parse_primary
    while (tok = peek) && tok.type == :operator
      prec = PRECEDENCE[tok.value]
      break if prec.nil? || prec < min_prec

      @pos += 1
      left = apply_op(tok.value, left, parse_expression(prec + 1))
    end
    left
  end

  def parse_primary
    tok = peek
    raise Error, 'Expresión incompleta.' if tok.nil?

    case tok.type
    when :lparen then parse_group
    when :operator then parse_unary(tok)
    when :num, :str then advance_value(tok.value)
    when :ident then parse_identifier(tok)
    else raise Error, 'Token inesperado en expresión.'
    end
  end

  def parse_group
    @pos += 1
    value = parse_expression(0)
    close = peek
    raise Error, 'Falta paréntesis de cierre.' if close.nil? || close.type != :rparen

    @pos += 1
    value
  end

  def parse_unary(tok)
    raise Error, 'Token inesperado en expresión.' unless tok.value == '-'

    @pos += 1
    -to_number(parse_primary)
  end

  def advance_value(value)
    @pos += 1
    value
  end

  def parse_identifier(tok)
    @pos += 1
    case tok.value
    when 'true' then true
    when 'false' then false
    when 'null' then nil
    # Referencia a una ruta del scope.
    else Jabvox::Flows::Engine::Template.get_by_path(@scope, tok.value)
    end
  end

  def to_number(value)
    return value if value.is_a?(Numeric)

    Float(value.to_s)
  rescue ArgumentError, TypeError
    0
  end

  def apply_op(operator, left, right)
    arithmetic(operator, left, right) || comparison(operator, left, right)
  end

  def arithmetic(operator, left, right)
    case operator
    # Suma numérica, o concatenación si alguno es string.
    when '+' then left.is_a?(String) || right.is_a?(String) ? "#{left}#{right}" : to_number(left) + to_number(right)
    when '-' then to_number(left) - to_number(right)
    when '*' then to_number(left) * to_number(right)
    when '/' then divide(left, right)
    when '%' then modulo(left, right)
    end
  end

  def divide(left, right)
    denominator = to_number(right)
    return Float::INFINITY if denominator.zero?

    to_number(left) / denominator.to_f
  end

  def modulo(left, right)
    denominator = to_number(right)
    denominator.zero? ? Float::NAN : to_number(left) % denominator
  end

  def comparison(operator, left, right)
    case operator
    when '==' then loose_equal(left, right)
    when '!=' then !loose_equal(left, right)
    when '===' then left == right
    when '!==' then left != right
    when '>' then to_number(left) > to_number(right)
    when '>=' then to_number(left) >= to_number(right)
    when '<' then to_number(left) < to_number(right)
    when '<=' then to_number(left) <= to_number(right)
    when '&&' then truthy?(left) && truthy?(right)
    when '||' then truthy?(left) ? left : right
    when 'contains' then left.to_s.include?(right.to_s)
    else raise Error, "Operador no soportado: #{operator}"
    end
  end

  # Igualdad LAXA equivalente a `==` de JS para los casos que los flujos usan:
  # número contra su texto ("5" == 5) sin igualar tipos incompatibles.
  def loose_equal(left, right)
    return true if left == right
    return false if left.nil? || right.nil?
    return left == right if [left, right].all? { |v| v == true || v == false }

    ln = Jabvox::Flows::Engine::Condition.numeric(left)
    rn = Jabvox::Flows::Engine::Condition.numeric(right)
    return ln == rn if ln && rn

    left.to_s == right.to_s
  end

  # Falsedad al estilo JS: nil, false, 0, '' son falsos.
  def truthy?(value)
    return false if value.nil? || value == false
    # `value` es de tipo arbitrario: `zero?` reventaría en true/String.
    return false if value == 0 || value == '' # rubocop:disable Style/NumericPredicate

    true
  end
end
