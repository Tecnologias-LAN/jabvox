class CreateJabvoxDialerCampaignContacts < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_dialer_campaign_contacts do |t|
      t.references :account, null: false, foreign_key: true
      t.references :jabvox_dialer_campaign, null: false, foreign_key: true,
                   index: { name: 'idx_dialer_contacts_on_campaign_id' }
      t.string :name_jabvox, default: ''
      t.string :phone_jabvox, null: false, default: ''
      t.string :status_jabvox, null: false, default: 'pending'
      t.integer :attempts_jabvox, null: false, default: 0
      t.datetime :last_attempt_at_jabvox

      t.timestamps
    end

    add_index :jabvox_dialer_campaign_contacts, :status_jabvox
  end
end
