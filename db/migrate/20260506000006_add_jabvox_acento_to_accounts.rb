class AddJabvoxAcentoToAccounts < ActiveRecord::Migration[7.0]
  def change
    add_column :accounts, :jabvox_acento_jabvox, :string, default: nil
  end
end
