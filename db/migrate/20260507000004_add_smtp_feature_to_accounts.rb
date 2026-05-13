class AddSmtpFeatureToAccounts < ActiveRecord::Migration[7.0]
  def change
    add_column :accounts, :jabvox_email_enabled_jabvox, :boolean, default: false, null: false
  end
end
