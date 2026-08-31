# frozen_string_literal: true

# logic.if — evalúa una condición con el evaluador COMPARTIDO y sale por
# true/false. Los operadores unarios ignoran el valor derecho.
class Jabvox::Flows::Nodes::Logic::IfNode < Jabvox::Flows::Nodes::Base
  type 'logic.if'
  label 'Condición'
  outputs 'true', 'false'

  def perform
    operator = Jabvox::Flows::Engine::Condition.normalize_operator(first_filled(param(:operator), 'equals'))
    left = param(:left)
    right = param(:right)
    matched = Jabvox::Flows::Engine::Condition.evaluate(left, operator, right)

    output = { 'result' => matched, 'matched' => matched, 'left' => left, 'operator' => operator }
    output['right'] = right unless Jabvox::Flows::Engine::Condition.unary?(operator)
    ok(output, output_port: matched ? 'true' : 'false')
  end
end
