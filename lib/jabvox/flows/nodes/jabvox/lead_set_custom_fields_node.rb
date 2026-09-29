# frozen_string_literal: true

# jabvox.lead.set_custom_fields — fija UN campo personalizado del lead. Los
# demás campos se CONSERVAN: la escritura es una fusión, no un reemplazo.
class Jabvox::Flows::Nodes::Jabvox::LeadSetCustomFieldsNode < Jabvox::Flows::Nodes::Jabvox::LeadSearchNode
  type 'jabvox.contact.set_custom_fields'
  # Tipo anterior: los flujos guardados lo siguen usando.
  aliases 'jabvox.lead.set_custom_fields'
  label 'Campos personalizados del Contacto'

  def perform
    field = param(:field).to_s.strip
    fail_with!('Elige el campo personalizado que quieres fijar.') if field.blank?

    lead = find_lead!(param(:leadId), 'el ID interno del lead')
    result = Jabvox::LeadCustomFieldsSanitizer.new(account, lead.custom_fields_jabvox,
                                                   field => param(:value)).call
    fail_with!("Campos personalizados no válidos: #{result.errors.join(', ')}.") unless result.valid?

    lead.update!(custom_fields_jabvox: result.data)
    { 'id' => lead.id, 'field' => field,
      'custom_fields_jabvox' => lead.custom_fields_jabvox || {}, 'updated' => true }
  end
end
