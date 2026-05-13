class CreateJabvoxFormSubmissions < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_form_submissions do |t|
      t.bigint :jabvox_form_id, null: false
      t.bigint :account_id, null: false
      t.jsonb :data_jabvox, default: {}
      t.string :ip_address_jabvox
      t.timestamps
    end

    add_index :jabvox_form_submissions, :jabvox_form_id
    add_index :jabvox_form_submissions, :account_id
    add_index :jabvox_form_submissions, :created_at
    add_foreign_key :jabvox_form_submissions, :jabvox_forms
    add_foreign_key :jabvox_form_submissions, :accounts
  end
end
