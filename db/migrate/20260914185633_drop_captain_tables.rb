# El módulo Captain se unificó dentro del Chat IA (Hermes): su código ya no existe, así que
# sus tablas quedan huérfanas. Ninguna tabla externa tiene FK hacia ellas, por lo que el
# borrado es seguro; se comprueba que estén vacías para no perder datos en instalaciones
# donde el módulo sí se llegó a usar.
class DropCaptainTables < ActiveRecord::Migration[7.1]
  TABLES = %w[
    copilot_messages
    copilot_threads
    captain_message_reports
    captain_faq_suggestions
    captain_faq_observations
    captain_scenarios
    captain_custom_tools
    captain_inboxes
    captain_documents
    captain_assistant_responses
    agent_sessions
    captain_assistants
  ].freeze

  def up
    TABLES.each do |table|
      next unless table_exists?(table)

      rows = select_value("SELECT COUNT(*) FROM #{quote_table_name(table)}").to_i
      raise ActiveRecord::IrreversibleMigration, "#{table} tiene #{rows} filas; revísalas antes de borrar la tabla." if rows.positive?

      drop_table table
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
