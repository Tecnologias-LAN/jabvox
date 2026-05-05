# frozen_string_literal: true

class AddCampaignsAffiliatesToKanbanFunnels < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_kanban_funnel_campaigns do |t|
      t.references :jabvox_kanban_funnel, null: false, foreign_key: true, index: false
      t.references :jabvox_campaign, null: false, foreign_key: true, index: false
      t.timestamps
    end

    add_index :jabvox_kanban_funnel_campaigns,
              [:jabvox_kanban_funnel_id, :jabvox_campaign_id],
              unique: true,
              name: 'idx_kanban_funnel_campaigns_unique'

    create_table :jabvox_kanban_funnel_affiliates do |t|
      t.references :jabvox_kanban_funnel, null: false, foreign_key: true, index: false
      t.references :jabvox_affiliate, null: false, foreign_key: true, index: false
      t.timestamps
    end

    add_index :jabvox_kanban_funnel_affiliates,
              [:jabvox_kanban_funnel_id, :jabvox_affiliate_id],
              unique: true,
              name: 'idx_kanban_funnel_affiliates_unique'
  end
end
