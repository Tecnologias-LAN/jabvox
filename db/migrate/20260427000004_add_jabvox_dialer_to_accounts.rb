class AddJabvoxDialerToAccounts < ActiveRecord::Migration[7.0]
  def change
    add_column :accounts, :jabvox_dialer_enabled_jabvox, :boolean, null: false, default: false
  end
end
