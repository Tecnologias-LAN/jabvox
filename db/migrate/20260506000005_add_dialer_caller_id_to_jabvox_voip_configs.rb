# frozen_string_literal: true

class AddDialerCallerIdToJabvoxVoipConfigs < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_voip_configs, :dialer_caller_id, :string, default: '', null: false
  end
end
