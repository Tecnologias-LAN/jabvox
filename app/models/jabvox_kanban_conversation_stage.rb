# == Schema Information
#
# Table name: jabvox_kanban_conversation_stages
#
#  id                      :bigint           not null, primary key
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint           not null
#  contact_id              :bigint
#  conversation_id         :bigint
#  created_by_id           :bigint
#  jabvox_kanban_funnel_id :bigint           not null
#  jabvox_kanban_stage_id  :bigint           not null
#  moved_by_id             :bigint
#
# Indexes
#
#  idx_on_account_id_contact_id_15c04b9163                   (account_id,contact_id)
#  index_jabvox_conv_stages_account                          (account_id)
#  index_jabvox_conv_stages_funnel                           (jabvox_kanban_funnel_id)
#  index_jabvox_conv_stages_stage                            (jabvox_kanban_stage_id)
#  index_jabvox_conv_stages_unique                           (conversation_id,jabvox_kanban_funnel_id) UNIQUE
#  index_jabvox_kanban_conversation_stages_on_created_by_id  (created_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (jabvox_kanban_funnel_id => jabvox_kanban_funnels.id)
#  fk_rails_...  (jabvox_kanban_stage_id => jabvox_kanban_stages.id)
#
class JabvoxKanbanConversationStage < ApplicationRecord
  self.table_name = 'jabvox_kanban_conversation_stages'

  belongs_to :conversation, optional: true
  # `contact` sustituye a `jabvox_lead`: campaña, afiliado y responsable viven ya en el
  # contacto. La asociación vieja se mantiene mientras existan filas antiguas.
  belongs_to :contact, optional: true
  belongs_to :jabvox_lead, optional: true
  belongs_to :jabvox_kanban_funnel
  belongs_to :jabvox_kanban_stage
  belongs_to :account
  belongs_to :moved_by, class_name: 'User', optional: true

  validates :conversation_id, uniqueness: { scope: :jabvox_kanban_funnel_id, allow_nil: true }
  validates :contact_id, uniqueness: { scope: :jabvox_kanban_funnel_id, allow_nil: true }
  validate :stage_belongs_to_funnel
  validate :conversation_belongs_to_account
  validate :has_conversation_or_lead

  after_commit :fire_stage_automations, on: [:create, :update]

  private

  def has_conversation_or_lead
    return if conversation_id.present? || contact_id.present?

    errors.add(:base, 'debe referenciar una conversación o un contacto')
  end

  def stage_belongs_to_funnel
    return if jabvox_kanban_stage&.jabvox_kanban_funnel_id == jabvox_kanban_funnel_id

    errors.add(:jabvox_kanban_stage, 'must belong to the selected funnel')
  end

  def conversation_belongs_to_account
    return if conversation.nil? || conversation.account_id == account_id

    errors.add(:conversation, 'must belong to the same account')
  end

  def fire_stage_automations
    JabvoxKanbanAutomationJob.perform_later(id)
  end
end
