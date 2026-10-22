# frozen_string_literal: true

# Token único por flujo para el disparador "Webhook entrante" (trigger.webhook).
# Forma la URL pública /webhooks/jabvox/flows/:token a la que un sistema externo
# hace POST para disparar el flujo. Es independiente del `secret` opcional del
# nodo (que es una segunda verificación dentro del payload).
class AddWebhookTokenToJabvoxFlows < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_flows, :webhook_token, :string
    add_index :jabvox_flows, :webhook_token, unique: true
  end
end
