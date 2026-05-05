class CreateJabvoxSmsMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_sms_messages do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :jabvox_sms_campaign, null: true, foreign_key: true, index: true
      t.references :jabvox_sms_provider, null: true, foreign_key: true, index: true
      t.references :contact, null: true, foreign_key: true, index: true
      t.string :phone, null: false
      t.text :message, null: false
      t.string :status, default: 'pending', null: false
      t.string :external_id
      t.text :error_message
      t.datetime :sent_at
      t.timestamps
    end

    add_index :jabvox_sms_messages, :status
  end
end
