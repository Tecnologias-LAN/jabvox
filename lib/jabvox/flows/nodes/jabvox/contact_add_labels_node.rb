# frozen_string_literal: true

# jabvox.contact.add_labels — etiqueta el CONTACTO, no la conversación: es un
# set SEPARADO, y el que sirve para marcar un lead y no reprocesarlo.
class Jabvox::Flows::Nodes::Jabvox::ContactAddLabelsNode < Jabvox::Flows::Nodes::Jabvox::LabelAddNode
  type 'jabvox.contact.add_labels'
  label 'Añadir etiquetas a contacto'

  MODE = :add
  ENTITY = :contact

  private

  def target
    find_contact!(param(:contactId))
  end

  def empty_message
    'Elige al menos una etiqueta para añadir al contacto.'
  end
end
