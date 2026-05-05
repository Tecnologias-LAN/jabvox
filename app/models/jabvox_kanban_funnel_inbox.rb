# == Schema Information
#
# Table name: jabvox_kanban_funnel_inboxes
#
#  id                      :bigint           not null, primary key
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  inbox_id                :bigint           not null
#  jabvox_kanban_funnel_id :bigint           not null
#
# Indexes
#
#  index_jabvox_funnel_inboxes_unique                             (jabvox_kanban_funnel_id,inbox_id) UNIQUE
#  index_jabvox_kanban_funnel_inboxes_on_inbox_id                 (inbox_id)
#  index_jabvox_kanban_funnel_inboxes_on_jabvox_kanban_funnel_id  (jabvox_kanban_funnel_id)
#
# Foreign Keys
#
#  fk_rails_...  (inbox_id => inboxes.id)
#  fk_rails_...  (jabvox_kanban_funnel_id => jabvox_kanban_funnels.id)
#
class JabvoxKanbanFunnelInbox < ApplicationRecord
  self.table_name = 'jabvox_kanban_funnel_inboxes'

  belongs_to :jabvox_kanban_funnel
  belongs_to :inbox

  validates :inbox_id, uniqueness: { scope: :jabvox_kanban_funnel_id }

  delegate :account_id, to: :jabvox_kanban_funnel
end
