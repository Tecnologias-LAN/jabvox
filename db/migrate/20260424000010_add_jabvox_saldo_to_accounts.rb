class AddJabvoxSaldoToAccounts < ActiveRecord::Migration[7.0]
  def change
    add_column :accounts, :jabvox_saldo_enabled_jabvox, :boolean, null: false, default: false
  end
end
