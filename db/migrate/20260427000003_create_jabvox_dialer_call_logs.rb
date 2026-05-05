class CreateJabvoxDialerCallLogs < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_dialer_call_logs do |t|
      t.references :account, null: false, foreign_key: true
      t.references :jabvox_dialer_campaign, null: false, foreign_key: true,
                   index: { name: 'idx_dialer_logs_on_campaign_id' }
      t.references :jabvox_dialer_campaign_contact, null: false, foreign_key: true,
                   index: { name: 'idx_dialer_logs_on_contact_id' }
      t.bigint :agent_id_jabvox
      t.string :phone_jabvox, null: false, default: ''
      t.string :status_jabvox, null: false, default: 'initiated'
      t.integer :duration_jabvox, default: 0
      t.datetime :started_at_jabvox
      t.datetime :ended_at_jabvox
      t.text :notes_jabvox

      t.timestamps
    end

    add_index :jabvox_dialer_call_logs, :started_at_jabvox
  end
end
