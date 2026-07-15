class AddDialerProviderPrefixToVoipConfigs < ActiveRecord::Migration[7.1]
  def change
    # Provider/carrier dial prefix required by the trunk (e.g. "0000"). This is
    # prepended to the already-normalized number right before dialing the trunk —
    # it is NOT the country code (that stays E.164 on the number/campaign).
    add_column :jabvox_voip_configs, :dialer_provider_prefix, :string, default: '', null: false
  end
end
