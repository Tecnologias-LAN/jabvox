# == Schema Information
#
# Table name: jabvox_kanban_funnel_campaigns
#
#  id                      :bigint           not null, primary key
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  jabvox_campaign_id      :bigint           not null
#  jabvox_kanban_funnel_id :bigint           not null
#
# Indexes
#
#  idx_kanban_funnel_campaigns_unique  (jabvox_kanban_funnel_id,jabvox_campaign_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (jabvox_campaign_id => jabvox_campaigns.id)
#  fk_rails_...  (jabvox_kanban_funnel_id => jabvox_kanban_funnels.id)
#
class JabvoxKanbanFunnelCampaign < ApplicationRecord
  belongs_to :jabvox_kanban_funnel
  belongs_to :jabvox_campaign

  validates :jabvox_campaign_id, uniqueness: { scope: :jabvox_kanban_funnel_id }
end
