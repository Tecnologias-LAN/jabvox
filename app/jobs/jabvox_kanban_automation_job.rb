class JabvoxKanbanAutomationJob < ApplicationJob
  queue_as :low

  def perform(conversation_stage_id)
    cs = JabvoxKanbanConversationStage.find_by(id: conversation_stage_id)
    return if cs.nil?

    Jabvox::KanbanAutomationExecutorService.new(cs).perform
  end
end
