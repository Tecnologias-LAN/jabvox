class CreateJabvoxWhatsappGroupsModule < ActiveRecord::Migration[7.1]
  def change
    add_module_flag
    create_groups_table
    create_members_table
  end

  private

  def add_module_flag
    return if column_exists?(:accounts, :jabvox_whatsapp_groups_enabled_jabvox)

    add_column :accounts, :jabvox_whatsapp_groups_enabled_jabvox, :boolean, default: false, null: false
  end

  def create_groups_table
    return if table_exists?(:jabvox_whatsapp_groups)

    create_table :jabvox_whatsapp_groups do |t|
      t.integer :account_id, null: false
      t.integer :inbox_id, null: false
      t.integer :conversation_id
      t.integer :created_by_id
      t.string :provider_group_id_jabvox
      t.string :name_jabvox, null: false
      t.text :description_jabvox
      t.string :avatar_url_jabvox
      t.text :invite_link_jabvox
      t.string :status_jabvox, null: false, default: 'active'
      t.jsonb :metadata_jabvox, null: false, default: {}
      t.timestamps
    end

    add_index :jabvox_whatsapp_groups, :account_id, name: 'idx_wa_groups_account'
    add_index :jabvox_whatsapp_groups, :inbox_id, name: 'idx_wa_groups_inbox'
    add_index :jabvox_whatsapp_groups, :provider_group_id_jabvox,
              unique: true, name: 'idx_wa_groups_provider_id', where: 'provider_group_id_jabvox IS NOT NULL'
  end

  def create_members_table
    return if table_exists?(:jabvox_whatsapp_group_members)

    create_table :jabvox_whatsapp_group_members do |t|
      t.integer :whatsapp_group_id, null: false
      t.integer :account_id, null: false
      t.integer :contact_id
      t.string :phone_number_jabvox, null: false
      t.string :name_jabvox
      t.string :role_jabvox, null: false, default: 'member'
      t.string :invite_status_jabvox, null: false, default: 'pending'
      t.datetime :joined_at_jabvox
      t.datetime :left_at_jabvox
      t.timestamps
    end

    add_index :jabvox_whatsapp_group_members, :whatsapp_group_id, name: 'idx_wa_group_members_group'
    add_index :jabvox_whatsapp_group_members, [:whatsapp_group_id, :phone_number_jabvox],
              unique: true, name: 'idx_wa_group_members_unique'
  end
end
