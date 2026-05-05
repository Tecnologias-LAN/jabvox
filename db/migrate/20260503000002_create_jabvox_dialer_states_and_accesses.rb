# frozen_string_literal: true

class CreateJabvoxDialerStatesAndAccesses < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_dialer_states do |t|
      t.bigint :account_id, null: false
      t.string :name, null: false
      t.string :color, default: '#64748b'
      t.integer :position, default: 0
      t.boolean :is_active, default: true, null: false
      t.timestamps
    end
    add_index :jabvox_dialer_states, :account_id

    create_table :jabvox_dialer_accesses do |t|
      t.bigint :account_id, null: false
      t.bigint :user_id, null: false
      t.boolean :can_access, default: false, null: false
      t.timestamps
    end
    add_index :jabvox_dialer_accesses, :account_id
    add_index :jabvox_dialer_accesses, %i[account_id user_id], unique: true, name: 'index_jabvox_dialer_accesses_account_user'
  end
end
