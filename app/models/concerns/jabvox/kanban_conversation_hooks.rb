module Jabvox::KanbanConversationHooks
  extend ActiveSupport::Concern

  included do
    after_create_commit :jabvox_place_in_kanban
    # Kanban stage rows reference the conversation with a plain (non-cascading)
    # FK, so a direct conversation.destroy! would raise PG::ForeignKeyViolation.
    # Clearing them on destroy makes deletion safe from EVERY path — not only
    # DeleteObjectJob, which already purges them — with no callbacks to run.
    has_many :jabvox_kanban_conversation_stages,
             class_name: 'JabvoxKanbanConversationStage',
             dependent: :delete_all
  end

  private

  def jabvox_place_in_kanban
    Jabvox::KanbanConversationPlacer.new(self).perform
  end
end
