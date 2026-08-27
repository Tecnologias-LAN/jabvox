# frozen_string_literal: true

# Permite administrar los secretos de la pasarela (API key, secret key de firma de
# webhook) desde el Super Admin, cifrados en reposo con ActiveRecord::Encryption.
# Antes vivían solo en variables de entorno; ahora la fuente de verdad es la BD.
#
# Las columnas guardan el ciphertext (encrypts en el modelo), no texto plano. El flag
# `sandbox` reemplaza la antigua variable BOLD_ENV para elegir modo pruebas/producción
# desde el panel.
class AddSecretsToJabvoxPaymentGatewayConfigs < ActiveRecord::Migration[7.1]
  def change
    # api_key/secret_key guardan el CIPHERTEXT (encrypts en el modelo). text porque el
    # cifrado + metadatos de ActiveRecord::Encryption ocupan bastante más que el claro.
    change_table :jabvox_payment_gateway_configs, bulk: true do |t|
      t.text :api_key
      t.text :secret_key
      t.boolean :sandbox, null: false, default: false
    end
  end
end
