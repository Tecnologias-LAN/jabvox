class AddAffiliateInboxIdsToJabvoxDialerCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_dialer_campaigns, :affiliate_ids_jabvox, :jsonb, default: []
    add_column :jabvox_dialer_campaigns, :inbox_ids_jabvox, :jsonb, default: []
  end
end
