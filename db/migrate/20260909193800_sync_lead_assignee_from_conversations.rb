# Sincroniza la asignación existente Lead <- Conversación, dando PRIORIDAD a la
# conversación (es la fuente de verdad). Para cada lead, si la conversación más
# reciente de su contacto tiene agente, se copia ese agente al lead. Si esa
# conversación no tiene agente, el lead conserva el suyo (no se pisa con NULL).
#
# Es un ajuste de datos de una sola vez; el comportamiento continuo lo mantiene
# el concern Jabvox::ConversationLeadAssignment + el servicio de sync inverso.
class SyncLeadAssigneeFromConversations < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    # Conversación más reciente por (account_id, contact_id) que TENGA agente.
    # DISTINCT ON toma la primera fila por grupo según el ORDER BY.
    execute(<<~SQL.squish)
      UPDATE jabvox_leads AS l
      SET assignee_id = c.assignee_id,
          updated_at = now()
      FROM (
        SELECT DISTINCT ON (account_id, contact_id)
               account_id, contact_id, assignee_id
        FROM conversations
        WHERE assignee_id IS NOT NULL
        ORDER BY account_id, contact_id, created_at DESC
      ) AS c
      WHERE l.account_id = c.account_id
        AND l.contact_id = c.contact_id
        AND l.assignee_id IS DISTINCT FROM c.assignee_id
    SQL
  end

  def down
    # No se revierte: es una sincronización de datos, no un cambio de esquema.
  end
end
