class CreateJabvoxSmsCampaigns < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_sms_campaigns do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :jabvox_sms_provider, null: true, foreign_key: true, index: true
      t.string :name, null: false
      t.text :description
      t.text :message, null: false
      t.string :status, default: 'draft', null: false
      t.integer :sent_count, default: 0, null: false
      t.integer :failed_count, default: 0, null: false
      t.jsonb :contact_ids, default: []
      t.timestamps
    end
  end
end
