# == Schema Information
#
# Table name: jabvox_kanban_funnel_affiliates
#
#  id                      :bigint           not null, primary key
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  jabvox_affiliate_id     :bigint           not null
#  jabvox_kanban_funnel_id :bigint           not null
#
# Indexes
#
#  idx_kanban_funnel_affiliates_unique  (jabvox_kanban_funnel_id,jabvox_affiliate_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (jabvox_affiliate_id => jabvox_affiliates.id)
#  fk_rails_...  (jabvox_kanban_funnel_id => jabvox_kanban_funnels.id)
#
class JabvoxKanbanFunnelAffiliate < ApplicationRecord
  belongs_to :jabvox_kanban_funnel
  belongs_to :jabvox_affiliate

  validates :jabvox_affiliate_id, uniqueness: { scope: :jabvox_kanban_funnel_id }
end
