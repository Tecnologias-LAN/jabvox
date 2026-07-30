class AddProviderConfigToChannelTwilioSms < ActiveRecord::Migration[7.1]
  def change
    return if column_exists?(:channel_twilio_sms, :provider_config)

    add_column :channel_twilio_sms, :provider_config, :jsonb, default: {}
  end
end
