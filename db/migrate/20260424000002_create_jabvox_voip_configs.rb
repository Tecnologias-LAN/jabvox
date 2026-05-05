class CreateJabvoxVoipConfigs < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_voip_configs do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.string :host, null: false, default: ''
      t.integer :port, null: false, default: 5038
      t.string :username, null: false, default: ''
      t.text :password
      t.string :context, null: false, default: 'clicktocall'
      t.string :dialer_context, default: ''
      t.timestamps
    end
  end
end
