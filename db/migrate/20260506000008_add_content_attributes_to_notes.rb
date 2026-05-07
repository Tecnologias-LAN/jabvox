class AddContentAttributesToNotes < ActiveRecord::Migration[7.0]
  def change
    add_column :notes, :content_attributes, :jsonb, default: {}
  end
end
