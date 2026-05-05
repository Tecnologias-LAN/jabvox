class AddFilterFieldsToJabvoxDialerCampaigns < ActiveRecord::Migration[7.0]
  def change
    add_column :jabvox_dialer_campaigns, :jabvox_campaign_id, :bigint
    add_column :jabvox_dialer_campaigns, :countries_jabvox, :jsonb, default: []
    add_column :jabvox_dialer_campaigns, :wrapup_time_jabvox, :integer, default: 30
    add_column :jabvox_dialer_campaigns, :lines_per_agent_jabvox, :integer, default: 1
    add_column :jabvox_dialer_campaigns, :management_state_ids_jabvox, :jsonb, default: []
    add_column :jabvox_dialer_campaigns, :agent_ids_jabvox, :jsonb, default: []

    add_index :jabvox_dialer_campaigns, :jabvox_campaign_id
    add_foreign_key :jabvox_dialer_campaigns, :jabvox_campaigns,
                    column: :jabvox_campaign_id, on_delete: :nullify
  end
end
