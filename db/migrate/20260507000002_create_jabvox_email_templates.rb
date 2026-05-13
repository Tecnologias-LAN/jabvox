class CreateJabvoxEmailTemplates < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_email_templates do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :subject
      t.text :body
      t.boolean :active, default: true, null: false
      t.timestamps
    end

    add_index :jabvox_email_templates, [:account_id, :name], unique: true
  end
end
