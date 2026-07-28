# frozen_string_literal: true

# API key PROPIA de cada cuenta para hablar con la plataforma Automations.
#
# POR QUÉ POR CUENTA Y NO SOLO LA PROVISION KEY MAESTRA: hasta ahora TODAS las
# operaciones viajaban con la clave maestra global. Si esa clave se rotaba o se
# desincronizaba, se caía la conexión de todas las cuentas a la vez. Con una key
# por cuenta, el operador la regenera en /admin de Automations, la pega en
# /super_admin/accounts/:id/account_automations y solo se restablece ESA cuenta.
#
# DOS COLUMNAS, NO UNA:
#   - api_key_jabvox: el valor, CIFRADO en reposo por Active Record Encryption
#     (ver AccountAutomationConfig#encrypts). Es `text` porque el ciphertext de
#     AR Encryption es un JSON en base64 mucho más largo que la key en claro
#     (`jbx_` + 32 hex = 36 caracteres).
#   - api_key_prefix_jabvox: los primeros caracteres EN CLARO. Existe para poder
#     pintar `•••• abcd1234` y para cotejar con el prefijo que muestra el panel
#     de Automations, sin descifrar nada y sin exponer la key completa. Si la
#     clave de cifrado se perdiera, el prefijo sigue permitiendo identificar qué
#     credencial estaba puesta.
#
# Ambas admiten NULL: las cuentas ya aprovisionadas no tienen key propia y deben
# seguir funcionando con la maestra (ver Automations::ProvisioningService).
class AddApiKeyToAccountAutomationConfigs < ActiveRecord::Migration[7.1]
  def change
    add_column :account_automation_configs, :api_key_jabvox, :text, null: true
    add_column :account_automation_configs, :api_key_prefix_jabvox, :string, null: true
    # Momento en que se pegó la key. Sirve para que el operador sepa si la que
    # tiene Jabvox es anterior a la última regeneración hecha en Automations.
    add_column :account_automation_configs, :api_key_set_at_jabvox, :datetime, null: true
  end
end
