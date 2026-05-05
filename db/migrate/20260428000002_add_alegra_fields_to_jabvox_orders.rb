class AddAlegraFieldsToJabvoxOrders < ActiveRecord::Migration[7.0]
  def change
    add_column :jabvox_orders, :alegra_id, :integer
    add_column :jabvox_orders, :alegra_number, :string
  end
end
