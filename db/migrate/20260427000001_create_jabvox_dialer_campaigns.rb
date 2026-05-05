class CreateJabvoxDialerCampaigns < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_dialer_campaigns do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name_jabvox, null: false, default: ''
      t.text :description_jabvox
      t.string :status_jabvox, null: false, default: 'draft'
      t.string :caller_id_jabvox, default: ''
      t.integer :max_concurrent_jabvox, null: false, default: 1
      t.integer :retry_count_jabvox, null: false, default: 0
      t.integer :retry_interval_jabvox, null: false, default: 60
      t.string :calling_hours_start_jabvox, default: '08:00'
      t.string :calling_hours_end_jabvox, default: '18:00'
      t.integer :total_contacts_jabvox, null: false, default: 0
      t.integer :dialed_count_jabvox, null: false, default: 0
      t.integer :answered_count_jabvox, null: false, default: 0
      t.integer :failed_count_jabvox, null: false, default: 0

      t.timestamps
    end
  end
end
