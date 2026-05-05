class CreateJabvoxIpWhitelists < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_ip_whitelists do |t|
      t.references :account, null: false, foreign_key: true
      t.string :ip, null: false, limit: 45
      t.boolean :is_active, null: false, default: true
      t.text :comment

      t.timestamps
    end

    add_index :jabvox_ip_whitelists, %i[account_id ip], unique: true
  end
end
