# Subtemas de tickets: un tema (categoría) puede tener un tema padre (self-reference).
# parent_id nulo = tema raíz; parent_id presente = subtema. Cambio mínimo y aditivo:
# no altera categorías existentes (todas quedan como raíz).
class AddParentToJabvoxTicketCategories < ActiveRecord::Migration[7.1]
  def change
    return if column_exists?(:jabvox_ticket_categories, :parent_id)

    add_column :jabvox_ticket_categories, :parent_id, :integer
    add_index :jabvox_ticket_categories, [:account_id, :parent_id],
              name: 'idx_ticket_categories_account_parent'
  end
end
