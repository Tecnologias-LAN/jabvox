# == Schema Information
#
# Table name: jabvox_kanban_conversation_stages
#
#  id                      :bigint           not null, primary key
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint           not null
#  conversation_id         :bigint           not null
#  jabvox_kanban_funnel_id :bigint           not null
#  jabvox_kanban_stage_id  :bigint           not null
#  moved_by_id             :bigint
#
# Indexes
#
#  index_jabvox_conv_stages_account  (account_id)
#  index_jabvox_conv_stages_funnel   (jabvox_kanban_funnel_id)
#  index_jabvox_conv_stages_stage    (jabvox_kanban_stage_id)
#  index_jabvox_conv_stages_unique   (conversation_id,jabvox_kanban_funnel_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (jabvox_kanban_funnel_id => jabvox_kanban_funnels.id)
#  fk_rails_...  (jabvox_kanban_stage_id => jabvox_kanban_stages.id)
#
class JabvoxKanbanConversationStage < ApplicationRecord
  self.table_name = 'jabvox_kanban_conversation_stages'

  belongs_to :conversation
  belongs_to :jabvox_kanban_funnel
  belongs_to :jabvox_kanban_stage
  belongs_to :account
  belongs_to :moved_by, class_name: 'User', optional: true

  validates :conversation_id, uniqueness: { scope: :jabvox_kanban_funnel_id }
  validate :stage_belongs_to_funnel
  validate :conversation_belongs_to_account

  private

  def stage_belongs_to_funnel
    return if jabvox_kanban_stage&.jabvox_kanban_funnel_id == jabvox_kanban_funnel_id

    errors.add(:jabvox_kanban_stage, 'must belong to the selected funnel')
  end

  def conversation_belongs_to_account
    return if conversation&.account_id == account_id

    errors.add(:conversation, 'must belong to the same account')
  end
end
