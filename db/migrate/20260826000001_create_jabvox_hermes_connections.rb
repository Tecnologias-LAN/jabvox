# frozen_string_literal: true

# Conexión a UN agente del Hermes de la cuenta (API Server OpenAI-compatible por prefijo).
#
# Tu Hermes expone cada agente en http://<host:puerto>/p/<agente>/v1 con su token propio.
# Varias conexiones por cuenta = varios agentes en el MISMO Hermes (mismo host:puerto,
# distinto prefijo+token). NO soporta varios Hermes: se valida que compartan host:puerto.
#
# Relación N:N con los agentes de Jabvox (jabvox_hermes_agents) vía tabla de unión: un agente
# Jabvox puede tener uno o varios agentes Hermes seleccionables en el Chat IA.
class CreateJabvoxHermesConnections < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_hermes_connections do |t|
      t.references :account, null: false, foreign_key: true
      t.string  :name_jabvox, null: false            # etiqueta visible (p.ej. "Agente Miguel")
      t.string  :hermes_agent_name_jabvox, null: false # nombre del agente en Hermes (agente-miguel)
      t.string  :base_url_jabvox, null: false         # http://host:puerto/p/<agente>/v1
      t.text    :token_jabvox                         # token del agente en Hermes (cifrado)
      t.string  :status_jabvox, null: false, default: 'unknown' # unknown|ok|error
      t.string  :last_error_jabvox
      t.datetime :last_check_at_jabvox
      t.timestamps
    end
    add_index :jabvox_hermes_connections, %i[account_id hermes_agent_name_jabvox], unique: true,
                                                                                   name: 'idx_hermes_conn_account_agent'

    # Unión N:N: agente Jabvox <-> conexiones Hermes
    create_table :jabvox_hermes_agent_connections do |t|
      t.references :hermes_agent, null: false,
                                  foreign_key: { to_table: :jabvox_hermes_agents }
      t.references :hermes_connection, null: false,
                                       foreign_key: { to_table: :jabvox_hermes_connections }
      t.timestamps
    end
    add_index :jabvox_hermes_agent_connections, %i[hermes_agent_id hermes_connection_id],
              unique: true, name: 'idx_hermes_agent_conn_unique'
  end
end
