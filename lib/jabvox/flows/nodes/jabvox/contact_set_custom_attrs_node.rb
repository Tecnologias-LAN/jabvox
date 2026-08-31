# frozen_string_literal: true

# jabvox.contact.set_custom_attrs — fija UN atributo personalizado del contacto
# sin tocar los demás.
class Jabvox::Flows::Nodes::Jabvox::ContactSetCustomAttrsNode < Jabvox::Flows::Nodes::Jabvox::Base
  type 'jabvox.contact.set_custom_attrs'
  label 'Fijar atributo de contacto'

  def perform
    attribute = param(:attribute).to_s.strip
    fail_with!('Elige el atributo personalizado que quieres fijar.') if attribute.blank?

    contact = find_contact!(param(:contactId))
    # FUSIÓN, no reemplazo: escribir el hash entero borraría los otros atributos.
    contact.update!(custom_attributes: (contact.custom_attributes || {}).merge(attribute => param(:value)))
    contact_view(contact).merge('contactId' => contact.id, 'attribute' => attribute,
                                'custom_attributes' => contact.custom_attributes)
  end
end
