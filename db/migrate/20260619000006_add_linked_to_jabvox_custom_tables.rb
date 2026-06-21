class AddLinkedToJabvoxCustomTables < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_custom_tables, :linked_to_jabvox, :string, default: nil
    add_index :jabvox_custom_tables, %i[account_id linked_to_jabvox],
              unique: true,
              where: "linked_to_jabvox IS NOT NULL",
              name: 'idx_jabvox_custom_tables_linked_to'
  end
end
