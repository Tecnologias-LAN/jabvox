# frozen_string_literal: true

# jabvox.conversation.add_labels — alias histórico de `jabvox.label.add`. Se
# mantiene para que los flujos guardados con él sigan ejecutándose.
class Jabvox::Flows::Nodes::Jabvox::ConversationAddLabelsNode < Jabvox::Flows::Nodes::Jabvox::LabelAddNode
  type 'jabvox.conversation.add_labels'
  label 'Añadir etiquetas a conversación'

  MODE = :add
  ENTITY = :conversation
end
