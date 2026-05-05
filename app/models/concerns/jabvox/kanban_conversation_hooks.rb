module Jabvox::KanbanConversationHooks
  extend ActiveSupport::Concern

  included do
    after_create_commit :jabvox_place_in_kanban
  end

  private

  def jabvox_place_in_kanban
    Jabvox::KanbanConversationPlacer.new(self).perform
  end
end
