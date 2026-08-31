# frozen_string_literal: true

# jabvox.contact.update — actualiza SOLO los campos configurados. Los que se
# dejan en blanco no se tocan: un '' borraría el dato que ya tenía.
class Jabvox::Flows::Nodes::Jabvox::ContactUpdateNode < Jabvox::Flows::Nodes::Jabvox::ContactCreateNode
  type 'jabvox.contact.update'
  label 'Actualizar contacto'

  def perform
    contact = find_contact!(param(:contactId))
    attrs = writable_attributes
    fail_with!('No se configuró ningún campo que actualizar.') if attrs.blank?

    # Los atributos personalizados se FUSIONAN: fijar uno no debe borrar el resto.
    attrs[:custom_attributes] = (contact.custom_attributes || {}).merge(attrs[:custom_attributes]) if
      attrs.key?(:custom_attributes)
    contact.update!(attrs)
    contact_view(contact).merge('contactId' => contact.id,
                                'custom_attributes' => contact.custom_attributes || {}, 'updated' => true)
  end
end
