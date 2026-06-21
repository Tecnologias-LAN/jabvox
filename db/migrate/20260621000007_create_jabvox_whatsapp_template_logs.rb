class CreateJabvoxWhatsappTemplateLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_whatsapp_template_logs do |t|
      t.references :jabvox_whatsapp_template, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.string :action, null: false
      t.text :description
      t.references :user, null: true, foreign_key: true
      t.timestamps
    end
    add_index :jabvox_whatsapp_template_logs, :action
  end
end
