# frozen_string_literal: true

# Token propio por AGENTE de Hermes. Cada agente Hermes (ligado 1:1 a un usuario de la app)
# tiene su token exclusivo: Hermes se autentica con él y Jabvox resuelve QUÉ agente/usuario
# es y aplica EXCLUSIVAMENTE sus permisos. El token no lo puede intervenir el LLM (viaja por
# header, se valida en backend, nunca en el prompt). Se guarda cifrado en reposo.
class AddAgentTokenToHermesAgents < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_hermes_agents, :agent_token_jabvox, :text
    add_index :jabvox_hermes_agents, :agent_token_jabvox, unique: true,
                                                          name: 'idx_hermes_agents_token', where: 'agent_token_jabvox IS NOT NULL'
  end
end
