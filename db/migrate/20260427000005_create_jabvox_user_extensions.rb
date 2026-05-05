class CreateJabvoxUserExtensions < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_user_extensions do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :extension_jabvox, null: false
      t.timestamps
    end

    add_index :jabvox_user_extensions, %i[account_id user_id], unique: true,
              name: 'idx_user_extensions_on_account_user'
    add_index :jabvox_user_extensions, %i[account_id extension_jabvox], unique: true,
              name: 'idx_user_extensions_on_account_ext'
  end
end
