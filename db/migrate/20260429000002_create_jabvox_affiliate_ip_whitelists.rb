class CreateJabvoxAffiliateIpWhitelists < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_affiliate_ip_whitelists do |t|
      t.references :jabvox_affiliate, null: false, foreign_key: true
      t.string :ip, limit: 45, null: false
      t.boolean :is_active, null: false, default: true
      t.text :comment

      t.timestamps
    end

    add_index :jabvox_affiliate_ip_whitelists, [:jabvox_affiliate_id, :ip], unique: true,
              name: 'idx_affiliate_ip_whitelists_on_affiliate_and_ip'
  end
end
