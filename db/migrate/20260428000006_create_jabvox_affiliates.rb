class CreateJabvoxAffiliates < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_affiliates do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.string :name, null: false
      t.string :account_code, null: false
      t.string :auth_token, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :jabvox_affiliates, :account_code, unique: true
    add_index :jabvox_affiliates, :auth_token, unique: true
    add_index :jabvox_affiliates, %i[account_id active]

    add_column :accounts, :jabvox_affiliates_enabled_jabvox, :boolean, null: false, default: false
  end
end
