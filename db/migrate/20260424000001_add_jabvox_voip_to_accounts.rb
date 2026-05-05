class AddJabvoxVoipToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :jabvox_voip_enabled_jabvox, :boolean, default: false, null: false
  end
end
