# == Schema Information
#
# Table name: jabvox_kanban_conversation_stages
#
#  id                      :bigint           not null, primary key
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint           not null
#  conversation_id         :bigint
#  jabvox_kanban_funnel_id :bigint           not null
#  jabvox_kanban_stage_id  :bigint           not null
#  jabvox_lead_id          :bigint
#  moved_by_id             :bigint
#
# Indexes
#
#  index_jabvox_conv_stages_account      (account_id)
#  index_jabvox_conv_stages_funnel       (jabvox_kanban_funnel_id)
#  index_jabvox_conv_stages_lead_funnel  (jabvox_lead_id,jabvox_kanban_funnel_id) UNIQUE WHERE (jabvox_lead_id IS NOT NULL)
#  index_jabvox_conv_stages_stage        (jabvox_kanban_stage_id)
#  index_jabvox_conv_stages_unique       (conversation_id,jabvox_kanban_funnel_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (jabvox_kanban_funnel_id => jabvox_kanban_funnels.id)
#  fk_rails_...  (jabvox_kanban_stage_id => jabvox_kanban_stages.id)
#  fk_rails_...  (jabvox_lead_id => jabvox_leads.id)
#
class JabvoxKanbanConversationStage < ApplicationRecord
  self.table_name = 'jabvox_kanban_conversation_stages'

  belongs_to :conversation, optional: true
  belongs_to :jabvox_lead, optional: true
  belongs_to :jabvox_kanban_funnel
  belongs_to :jabvox_kanban_stage
  belongs_to :account
  belongs_to :moved_by, class_name: 'User', optional: true

  validates :conversation_id, uniqueness: { scope: :jabvox_kanban_funnel_id, allow_nil: true }
  validates :jabvox_lead_id, uniqueness: { scope: :jabvox_kanban_funnel_id, allow_nil: true }
  validate :stage_belongs_to_funnel
  validate :conversation_belongs_to_account
  validate :has_conversation_or_lead

  private

  def has_conversation_or_lead
    return if conversation_id.present? || jabvox_lead_id.present?

    errors.add(:base, 'must reference a conversation or a lead')
  end

  def stage_belongs_to_funnel
    return if jabvox_kanban_stage&.jabvox_kanban_funnel_id == jabvox_kanban_funnel_id

    errors.add(:jabvox_kanban_stage, 'must belong to the selected funnel')
  end

  def conversation_belongs_to_account
    return if conversation.nil? || conversation.account_id == account_id

    errors.add(:conversation, 'must belong to the same account')
  end
end
