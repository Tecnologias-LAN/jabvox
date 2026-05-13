class CreateJabvoxFormConfigs < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_form_configs do |t|
      t.bigint :account_id, null: false
      t.string :base_url_jabvox, default: ''
      t.integer :max_forms_jabvox, default: 10, null: false
      t.timestamps
    end

    add_index :jabvox_form_configs, :account_id, unique: true
    add_foreign_key :jabvox_form_configs, :accounts
  end
end
