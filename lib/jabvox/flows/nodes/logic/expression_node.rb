# frozen_string_literal: true

# logic.expression — evalúa una expresión ACOTADA (sin eval) y guarda el
# resultado en una variable. Admite rutas nativas (`vars.total > 100`) y
# plantillas (`{{trigger.monto}} > 100`).
class Jabvox::Flows::Nodes::Logic::ExpressionNode < Jabvox::Flows::Nodes::Base
  type 'logic.expression'
  label 'Expresión'

  def perform
    # Se parte del param CRUDO a propósito: el motor ya resolvió las plantillas
    # en `params`, y ese texto sustituido entraría en la expresión como SINTAXIS
    # VIVA (un valor con comillas podría inyectar operadores). Aquí se interpola
    # de nuevo, pero insertando cada valor como literal.
    raw = raw_expression
    fail_with!('Falta la expresión a evaluar.') if raw.strip.blank?

    expression = interpolate(raw)
    result = Jabvox::Flows::Engine::Expression.evaluate(expression, ctx)
    assign(result)
    # `expression` ya interpolada: sin esto, depurar un false es adivinar.
    { 'result' => result, 'expression' => expression }
  rescue Jabvox::Flows::Engine::Expression::Error => e
    failure(e.message)
  end

  private

  def raw_expression
    original = node.params.is_a?(Hash) ? node.params['expression'] : nil
    original.nil? ? param(:expression).to_s : original.to_s
  end

  def assign(result)
    assign_to = first_filled(param(:assignTo), 'result')
    ctx.vars[assign_to] = result if assign_to.present?
  end

  # Cada {{ruta}} se sustituye por el LITERAL del valor: números y booleanos tal
  # cual, el resto como cadena entrecomillada con los escapes que el tokenizador
  # del motor entiende. Así el payload nunca altera la estructura de la expresión.
  def interpolate(expression)
    return expression unless expression.include?('{{')

    expression.gsub(Jabvox::Flows::Engine::Template::TEMPLATE_RE) do
      literal(Jabvox::Flows::Engine::Template.resolve_string("{{#{Regexp.last_match(1).strip}}}", ctx))
    end
  end

  def literal(value)
    case value
    when nil then 'null'
    when Numeric, true, false then value.to_s
    when Hash, Array then quote(value.to_json)
    else quote(value.to_s)
    end
  end

  # Comillas dobles escapando la barra y la propia comilla: es lo que revierte
  # el `gsub(/\\(.)/)` del tokenizador, así que el texto vuelve intacto.
  def quote(text)
    "\"#{text.gsub('\\', '\\\\\\\\').gsub('"', '\\"')}\""
  end
end
