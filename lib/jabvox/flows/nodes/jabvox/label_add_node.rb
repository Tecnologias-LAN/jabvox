# frozen_string_literal: true

# jabvox.label.add — añade etiquetas a una CONVERSACIÓN.
class Jabvox::Flows::Nodes::Jabvox::LabelAddNode < Jabvox::Flows::Nodes::Jabvox::Base
  type 'jabvox.label.add'
  label 'Añadir etiqueta a conversación'

  MODE = :add
  ENTITY = :conversation

  def perform
    labels = Jabvox::Flows::Nodes::LabelWriter.normalize(param(:labels))
    fail_with!(empty_message) if labels.empty?

    Jabvox::Flows::Nodes::LabelWriter.assert_exist!(account, labels, self.class::MODE)
    record = target
    final = Jabvox::Flows::Nodes::LabelWriter.apply(record, labels, self.class::MODE)
    { 'id' => record.id, 'entity' => self.class::ENTITY.to_s, 'mode' => self.class::MODE.to_s,
      'labels' => final, 'applied' => labels, 'payload' => final }
  end

  private

  def target
    find_conversation!(param(:conversationId))
  end

  def empty_message
    'Elige al menos una etiqueta para añadir.'
  end
end
