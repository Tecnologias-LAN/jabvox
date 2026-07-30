class AddIconColorToCategories < ActiveRecord::Migration[7.1]
  def change
    return if column_exists?(:categories, :icon_color)

    add_column :categories, :icon_color, :string, default: ''
  end
end
