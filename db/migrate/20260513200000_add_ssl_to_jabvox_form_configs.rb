class AddSslToJabvoxFormConfigs < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_form_configs, :ssl_status, :string, default: 'none', null: false
    add_column :jabvox_form_configs, :ssl_cert, :text
    add_column :jabvox_form_configs, :ssl_key, :text
    add_column :jabvox_form_configs, :ssl_expires_at, :datetime
    add_column :jabvox_form_configs, :ssl_error, :string, limit: 500
    add_column :jabvox_form_configs, :ssl_provisioned_at, :datetime
    add_column :jabvox_form_configs, :acme_account_key, :text
  end
end
