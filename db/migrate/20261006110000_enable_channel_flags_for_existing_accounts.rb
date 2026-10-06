# Los canales (WhatsApp, SMS, API, Telegram, Line, llamada de WhatsApp) pasan a estar
# gateados por feature para que cada cuenta vea solo los que puede usar. Un flag nuevo nace
# apagado en las cuentas que YA existen —`enabled: true` en features.yml solo aplica a
# cuentas nuevas—, así que sin este backfill WhatsApp desaparecería del listado de todo el
# mundo al desplegar. Se encienden para todos y desde ahí se apagan uno a uno por cuenta.
class EnableChannelFlagsForExistingAccounts < ActiveRecord::Migration[7.1]
  CHANNEL_FLAGS = %w[channel_whatsapp channel_sms channel_api channel_telegram
                     channel_line channel_whatsapp_call].freeze

  def up
    Account.find_each do |account|
      account.enable_features(*CHANNEL_FLAGS)
      account.save!
    end
  end

  def down
    Account.find_each do |account|
      account.disable_features(*CHANNEL_FLAGS)
      account.save!
    end
  end
end
