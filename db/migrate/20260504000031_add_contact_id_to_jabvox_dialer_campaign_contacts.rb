class AddContactIdToJabvoxDialerCampaignContacts < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_dialer_campaign_contacts, :contact_id, :bigint
    add_index :jabvox_dialer_campaign_contacts, :contact_id
  end
end
