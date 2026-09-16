class AddJabvoxWhatsappFlowsEnabledToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :jabvox_whatsapp_flows_enabled_jabvox, :boolean, null: false, default: false
  end
end
