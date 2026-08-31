# frozen_string_literal: true

# jabvox.label.remove — quita etiquetas de una CONVERSACIÓN.
class Jabvox::Flows::Nodes::Jabvox::LabelRemoveNode < Jabvox::Flows::Nodes::Jabvox::LabelAddNode
  type 'jabvox.label.remove'
  label 'Quitar etiqueta de conversación'

  MODE = :remove
  ENTITY = :conversation

  private

  def empty_message
    'Elige al menos una etiqueta para quitar.'
  end
end
