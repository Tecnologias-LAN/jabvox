# frozen_string_literal: true

# jabvox.kanban.move_conversation — coloca la conversación en una etapa del
# embudo. Siempre se resuelve por display_id (el número de la URL), nunca por PK.
class Jabvox::Flows::Nodes::Jabvox::KanbanMoveConversationNode < Jabvox::Flows::Nodes::Jabvox::KanbanBase
  type 'jabvox.kanban.move_conversation'
  label 'Mover conversación en Kanban'

  def perform
    funnel = find_funnel!(param(:funnelId))
    stage = find_stage_in_funnel!(param(:stageId), funnel)
    conversation = find_conversation!(param(:conversationId), 'el número de conversación')
    row, previous = place!(funnel, stage, conversation_id: conversation.id)
    kanban_view(row, funnel, stage, previous)
      .merge('conversation_id' => conversation.display_id, 'conversationId' => conversation.display_id)
  end
end
