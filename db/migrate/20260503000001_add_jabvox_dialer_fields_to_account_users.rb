# frozen_string_literal: true

class AddJabvoxDialerFieldsToAccountUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :account_users, :jabvox_dialer_state, :string, default: 'inactive'
    add_column :account_users, :jabvox_app_state_changed_at, :datetime
  end
end
