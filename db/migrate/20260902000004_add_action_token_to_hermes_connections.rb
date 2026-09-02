# frozen_string_literal: true

# El token de ACCIÓN (Hermes → Jabvox) pasa a vivir en la CONEXIÓN Hermes, no en el
# agente de la app. Así cada Hermes (cada JabvoxHermesConnection) tiene su propio token
# único: p. ej. el agente "Gerencia" con 2 Hermes (Ana + Agente-Miguel) obtiene 2 tokens
# distintos, uno por cada Hermes.
#
# action_token_jabvox se cifra a nivel de aplicación (deterministic, para poder resolver
# la conexión por su token en authenticate). Se genera uno para cada conexión existente
# que no lo tenga, de modo que el próximo deploy deje TODAS las conexiones operativas
# aunque las migraciones anteriores ya hayan corrido.
class AddActionTokenToHermesConnections < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    unless column_exists?(:jabvox_hermes_connections, :action_token_jabvox)
      add_column :jabvox_hermes_connections, :action_token_jabvox, :text
    end

    # Índice único parcial (solo filas con token), como el de los agentes.
    unless index_exists?(:jabvox_hermes_connections, :action_token_jabvox,
                         name: 'idx_hermes_conn_action_token')
      add_index :jabvox_hermes_connections, :action_token_jabvox, unique: true,
                where: 'action_token_jabvox IS NOT NULL',
                name: 'idx_hermes_conn_action_token',
                algorithm: :concurrently
    end

    # Cardinalidad: un Hermes (conexión) pertenece a UN solo agente de la cuenta. Antes de
    # imponer el índice único, deduplica dejando el vínculo más antiguo por conexión.
    dedupe_agent_connections

    unless index_exists?(:jabvox_hermes_agent_connections, :hermes_connection_id,
                         name: 'idx_hermes_conn_single_agent')
      add_index :jabvox_hermes_agent_connections, :hermes_connection_id, unique: true,
                name: 'idx_hermes_conn_single_agent', algorithm: :concurrently
    end

    return unless Jabvox.encryption_configured?

    # Genera token de acción para cada conexión que no lo tenga (guardado cifrado por el
    # `encrypts` del modelo). update! dispara el cifrado; rescue por si alguna fila falla.
    JabvoxHermesConnection.reset_column_information
    JabvoxHermesConnection.find_each do |conn|
      next if conn.action_token_jabvox.present?

      conn.update!(action_token_jabvox: JabvoxHermesConnection.generate_action_token(conn.account_id))
    rescue StandardError => e
      Rails.logger.warn("[hermes-conn-action-token] conn ##{conn.id}: #{e.class} #{e.message}")
    end
  end

  # Deja solo el vínculo agente↔conexión más antiguo por cada conexión (para poder imponer
  # que una conexión tenga un único agente). Ejecuta en SQL puro para no depender del modelo.
  def dedupe_agent_connections
    execute(<<~SQL.squish)
      DELETE FROM jabvox_hermes_agent_connections a
      USING jabvox_hermes_agent_connections b
      WHERE a.hermes_connection_id = b.hermes_connection_id
        AND a.id > b.id
    SQL
  end

  def down
    if index_exists?(:jabvox_hermes_agent_connections, :hermes_connection_id,
                     name: 'idx_hermes_conn_single_agent')
      remove_index :jabvox_hermes_agent_connections, name: 'idx_hermes_conn_single_agent'
    end
    if index_exists?(:jabvox_hermes_connections, :action_token_jabvox,
                     name: 'idx_hermes_conn_action_token')
      remove_index :jabvox_hermes_connections, name: 'idx_hermes_conn_action_token'
    end
    remove_column :jabvox_hermes_connections, :action_token_jabvox if column_exists?(:jabvox_hermes_connections, :action_token_jabvox)
  end
end
