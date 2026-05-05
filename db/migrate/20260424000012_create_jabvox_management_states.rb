class CreateJabvoxManagementStates < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_management_states do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name_jabvox, null: false, default: ''
      t.string :color_jabvox, null: false, default: '#6366f1'
      t.boolean :is_active_jabvox, null: false, default: true
      t.integer :position_jabvox, null: false, default: 0
      t.timestamps
    end
  end
end
