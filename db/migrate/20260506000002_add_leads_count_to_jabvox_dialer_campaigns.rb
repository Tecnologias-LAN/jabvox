class AddLeadsCountToJabvoxDialerCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_dialer_campaigns, :leads_count_jabvox, :integer, default: 0, null: false
  end
end
