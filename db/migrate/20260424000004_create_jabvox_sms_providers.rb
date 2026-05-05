class CreateJabvoxSmsProviders < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_sms_providers do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.string :name, null: false
      t.string :base_url, null: false
      t.string :api_user, null: false
      t.text :api_password
      t.boolean :active, default: true, null: false
      t.timestamps
    end
  end
end
