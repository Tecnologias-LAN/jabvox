class CreateJabvoxIntegrationConfigs < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_integration_configs do |t|
      t.bigint :account_id, null: false
      t.string :integration_type_jabvox, default: 'alegra'
      t.text :integration_email_jabvox
      t.text :integration_token_jabvox
      t.string :company_name_jabvox
      t.string :company_nit_jabvox
      t.text :company_address_jabvox
      t.string :company_phone_jabvox
      t.string :company_email_jabvox
      t.string :company_website_jabvox
      t.text :company_logo_jabvox
      t.timestamps
    end

    add_index :jabvox_integration_configs, :account_id, unique: true
    add_foreign_key :jabvox_integration_configs, :accounts
  end
end
