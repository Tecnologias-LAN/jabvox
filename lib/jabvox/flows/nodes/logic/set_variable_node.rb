# frozen_string_literal: true

# logic.set_variable — define o actualiza una variable de ejecución `{{vars.x}}`.
class Jabvox::Flows::Nodes::Logic::SetVariableNode < Jabvox::Flows::Nodes::Base
  type 'logic.set_variable'
  label 'Definir variable'

  def perform
    name = param(:name).to_s.strip
    fail_with!('Falta el nombre de la variable.') if name.blank?

    value = param(:value)
    ctx.vars[name] = value
    { name => value, 'name' => name, 'value' => value }
  end
end
