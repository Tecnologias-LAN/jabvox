class CreateJabvoxSmtpConfigs < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_smtp_configs do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.string :from_name
      t.string :from_email
      t.string :address
      t.integer :port, default: 587
      t.string :domain
      t.string :username
      t.text :password
      t.string :authentication, default: 'login'
      t.boolean :enable_starttls_auto, default: true
      t.boolean :enable_ssl_tls, default: false
      t.boolean :verified, default: false
      t.timestamps
    end
  end
end
