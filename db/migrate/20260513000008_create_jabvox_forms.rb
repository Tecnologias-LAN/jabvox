class CreateJabvoxForms < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_forms do |t|
      t.bigint :account_id, null: false
      t.string :name_jabvox, null: false
      t.string :slug_jabvox, null: false
      t.jsonb :header_jabvox, default: {}
      t.jsonb :footer_jabvox, default: {}
      t.jsonb :fields_jabvox, default: []
      t.jsonb :submit_actions_jabvox, default: {}
      t.string :submit_button_text_jabvox, default: 'Enviar'
      t.boolean :active_jabvox, default: true, null: false
      t.timestamps
    end

    add_index :jabvox_forms, :account_id
    add_index :jabvox_forms, :slug_jabvox, unique: true
    add_foreign_key :jabvox_forms, :accounts
  end
end
