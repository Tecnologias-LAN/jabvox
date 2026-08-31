# frozen_string_literal: true

# jabvox.contact.remove_labels — quita etiquetas del CONTACTO.
class Jabvox::Flows::Nodes::Jabvox::ContactRemoveLabelsNode < Jabvox::Flows::Nodes::Jabvox::ContactAddLabelsNode
  type 'jabvox.contact.remove_labels'
  label 'Quitar etiquetas de contacto'

  MODE = :remove
  ENTITY = :contact

  private

  def empty_message
    'Elige al menos una etiqueta para quitar del contacto.'
  end
end
