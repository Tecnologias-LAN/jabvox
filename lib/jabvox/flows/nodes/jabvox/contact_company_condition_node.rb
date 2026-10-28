# frozen_string_literal: true

# jabvox.contact.company_is — condición: ¿la EMPRESA (entidad) del contacto es la
# indicada? Sale por los puertos true/false, como logic.if, pero leyendo el
# company_id del contacto. Permite "cliente existente -> etiquetar soporte" dentro
# de un flujo. Reutiliza el evaluador compartido de condiciones.
#
# Operadores: equals / not_equals (contra el id de empresa) y present / not_present
# (¿el contacto tiene empresa?). El valor derecho (companyId) se ignora en los unarios.
class Jabvox::Flows::Nodes::Jabvox::ContactCompanyConditionNode < Jabvox::Flows::Nodes::Jabvox::Base
  type 'jabvox.contact.company_is'
  label 'Empresa del contacto'
  outputs 'true', 'false'

  def perform
    contact = find_contact!(param(:contactId))
    operator = Jabvox::Flows::Engine::Condition.normalize_operator(first_filled(param(:operator), 'equals'))
    left = contact.company_id
    right = param(:companyId)

    matched = Jabvox::Flows::Engine::Condition.evaluate(left, operator, right)

    output = { 'result' => matched, 'matched' => matched,
               'contactId' => contact.id, 'companyId' => contact.company_id, 'operator' => operator }
    output['expected'] = right unless Jabvox::Flows::Engine::Condition.unary?(operator)
    ok(output, output_port: matched ? 'true' : 'false')
  end
end
