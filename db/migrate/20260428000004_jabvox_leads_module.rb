class JabvoxLeadsModule < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :jabvox_leads_enabled_jabvox, :boolean, default: false, null: false

    create_table :jabvox_campaigns do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name_jabvox, null: false
      t.timestamps
    end
    add_index :jabvox_campaigns, %i[account_id name_jabvox], unique: true

    create_table :jabvox_leads do |t|
      t.references :account, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.references :jabvox_campaign, null: true, foreign_key: true
      t.timestamps
    end
    add_index :jabvox_leads, %i[account_id contact_id], unique: true
    add_index :jabvox_leads, %i[account_id jabvox_campaign_id]
  end
end
