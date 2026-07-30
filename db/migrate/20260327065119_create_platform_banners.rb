class CreatePlatformBanners < ActiveRecord::Migration[7.1]
  def change
    return if table_exists?(:platform_banners)

    create_table :platform_banners do |t|
      t.text :banner_message, null: false
      t.integer :banner_type, null: false, default: 0
      t.boolean :active, default: true, null: false

      t.timestamps
    end
  end
end
