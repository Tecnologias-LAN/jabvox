# frozen_string_literal: true

class AddJabvoxDialerStateChangedAtToAccountUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :account_users, :jabvox_dialer_state_changed_at, :datetime
  end
end
