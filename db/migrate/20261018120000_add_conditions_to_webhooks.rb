# frozen_string_literal: true

# Reglas opcionales de entrega por webhook (Jabvox). Con `conditions` vacío/null el
# webhook se comporta igual que siempre. Permite: limitar a ciertas bandejas,
# excluir conversaciones por etiqueta, y responder solo dentro del horario del inbox.
# Lo usa principalmente el webhook de Hermes (Chat IA) para controlar cuándo responde.
class AddConditionsToWebhooks < ActiveRecord::Migration[7.1]
  def change
    add_column :webhooks, :conditions, :jsonb, default: {}, null: false
  end
end
