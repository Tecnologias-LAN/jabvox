# Liga un modelo de Chat IA a un AGENTE de Hermes: cada agente tiene su propio modelo.
# En la pantalla de Modelos, el admin ve/asigna a qué agente pertenece cada modelo, y el
# sync bidireccional mantiene esos modelos en Hermes y viceversa.
class AddHermesAgentToAiChatModels < ActiveRecord::Migration[7.1]
  def change
    add_reference :jabvox_ai_chat_models, :hermes_agent,
                  foreign_key: { to_table: :jabvox_hermes_agents }, null: true
  end
end
