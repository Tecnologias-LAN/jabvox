class CreateJabvoxFieldVisibilities < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_field_visibilities do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :field_name, null: false
      t.boolean :can_view, default: true, null: false
      t.timestamps
    end

    add_index :jabvox_field_visibilities, [:account_id, :user_id, :field_name],
              unique: true, name: 'idx_jabvox_field_visibility_unique'
  end
end
