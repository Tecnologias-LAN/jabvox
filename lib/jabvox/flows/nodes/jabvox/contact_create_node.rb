# frozen_string_literal: true

# jabvox.contact.create — crea un contacto en la cuenta.
class Jabvox::Flows::Nodes::Jabvox::ContactCreateNode < Jabvox::Flows::Nodes::Jabvox::Base
  type 'jabvox.contact.create'
  label 'Crear contacto'

  def perform
    attrs = writable_attributes
    fail_with!('Un contacto necesita al menos un nombre, un email o un teléfono.') if attrs.blank?

    contact = account.contacts.create!(attrs)
    # `contactId` se expone además del `id` para poder encadenar sin ambigüedad.
    contact_view(contact).merge('contactId' => contact.id,
                                'custom_attributes' => contact.custom_attributes || {})
  end

  private

  # Solo las claves REALMENTE configuradas: una vacía borraría el dato existente.
  def writable_attributes
    attrs = { name: param(:name), email: param(:email),
              phone_number: param(:phone_number), identifier: param(:identifier) }
            .reject { |_, v| blank_param?(v) }
    custom = clean_map(param(:custom_attributes))
    custom.present? ? attrs.merge(custom_attributes: custom) : attrs
  end

  def clean_map(raw)
    return {} unless raw.is_a?(Hash)

    raw.reject { |k, v| k.to_s.strip.empty? || blank_param?(v) }.transform_keys(&:to_s)
  end
end
