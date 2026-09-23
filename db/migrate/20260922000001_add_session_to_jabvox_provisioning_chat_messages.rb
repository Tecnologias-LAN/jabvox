# frozen_string_literal: true

# El Chat Aprovisionador era un hilo ÚNICO por cuenta: sin session_id, todos los mensajes
# de todos los usuarios se mezclaban en una sola lista y no había forma de abrir una
# conversación nueva. Se añade session_id para que funcione como el Chat IA (varias
# conversaciones, cada una con su historial).
#
# Los mensajes existentes se agrupan en una sesión 'legacy' para no perderlos ni dejarlos
# huérfanos: siguen visibles como una conversación más.
class AddSessionToJabvoxProvisioningChatMessages < ActiveRecord::Migration[7.1]
  def up
    add_column :jabvox_provisioning_chat_messages, :session_id, :string
    execute(<<~SQL.squish)
      UPDATE jabvox_provisioning_chat_messages SET session_id = 'legacy' WHERE session_id IS NULL
    SQL
    change_column_null :jabvox_provisioning_chat_messages, :session_id, false

    # El índice cubre la consulta real: mensajes de UNA sesión de UNA cuenta en orden.
    add_index :jabvox_provisioning_chat_messages,
              %i[account_id session_id created_at],
              name: 'idx_jabvox_prov_chat_on_account_session_created'
  end

  def down
    remove_index :jabvox_provisioning_chat_messages, name: 'idx_jabvox_prov_chat_on_account_session_created'
    remove_column :jabvox_provisioning_chat_messages, :session_id
  end
end
