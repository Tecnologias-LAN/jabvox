class CreateJabvoxUnitsOfMeasure < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_units_of_measure do |t|
      t.bigint :account_id, null: false
      t.string :name_jabvox, null: false
      t.string :abbreviation_jabvox
      t.boolean :active_jabvox, null: false, default: true
      t.timestamps
    end

    add_index :jabvox_units_of_measure, :account_id
    add_index :jabvox_units_of_measure, [:account_id, :name_jabvox], unique: true, name: 'index_jabvox_units_account_name'
    add_foreign_key :jabvox_units_of_measure, :accounts
  end
end
