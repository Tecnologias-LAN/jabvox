# frozen_string_literal: true

class CreateJabvoxAppStateLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_app_state_logs do |t|
      t.references :account, null: false, foreign_key: true
      t.bigint :user_id, null: false
      t.integer :app_state_id
      t.datetime :started_at, null: false
      t.datetime :ended_at

      t.timestamps
    end

    add_index :jabvox_app_state_logs, %i[account_id user_id started_at]
    add_index :jabvox_app_state_logs, %i[user_id ended_at]
  end
end
