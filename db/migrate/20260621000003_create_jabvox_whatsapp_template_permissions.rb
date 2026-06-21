class CreateJabvoxWhatsappTemplatePermissions < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_whatsapp_template_permissions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.boolean :can_manage, null: false, default: false
      t.timestamps
    end

    add_index :jabvox_whatsapp_template_permissions, [:account_id, :user_id], unique: true,
              name: 'idx_jabvox_wa_template_perms_account_user'
  end
end
