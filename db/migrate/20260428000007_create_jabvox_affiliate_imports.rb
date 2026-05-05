class CreateJabvoxAffiliateImports < ActiveRecord::Migration[7.0]
  def change
    create_table :jabvox_affiliate_imports do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :jabvox_affiliate, null: false, foreign_key: true, index: true
      t.string :filename
      t.integer :rows_total, null: false, default: 0
      t.integer :rows_ok, null: false, default: 0
      t.integer :rows_failed, null: false, default: 0
      t.integer :import_type, null: false, default: 0
      t.timestamps
    end
  end
end
