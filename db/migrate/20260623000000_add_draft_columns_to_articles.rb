class AddDraftColumnsToArticles < ActiveRecord::Migration[7.1]
  def change
    return if column_exists?(:articles, :draft_title)

    add_column :articles, :draft_title, :string
    add_column :articles, :draft_content, :text
  end
end
