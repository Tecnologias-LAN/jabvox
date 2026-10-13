class DropHelpCenterTables < ActiveRecord::Migration[7.1]
  # El centro de ayuda (portales, articulos, categorias) se retiro del producto.
  # Esta migracion solo avanza: no hay `down` porque los datos no se recuperan.
  def up
    remove_foreign_key :inboxes, :portals, if_exists: true
    remove_column :inboxes, :portal_id, if_exists: true

    drop_table :article_embeddings, if_exists: true
    drop_table :related_categories, if_exists: true
    drop_table :folders, if_exists: true
    drop_table :articles, if_exists: true
    drop_table :categories, if_exists: true
    drop_table :portals_members, if_exists: true
    drop_table :portals, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
