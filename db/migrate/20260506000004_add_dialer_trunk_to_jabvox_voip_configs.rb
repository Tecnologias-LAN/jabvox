class AddDialerTrunkToJabvoxVoipConfigs < ActiveRecord::Migration[7.0]
  def change
    add_column :jabvox_voip_configs, :dialer_trunk, :string, default: '', null: false
  end
end
