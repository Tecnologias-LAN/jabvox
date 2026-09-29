# frozen_string_literal: true

# Rellena `contact_id` en `jabvox_custom_table_rows` desde su lead.
#
# La migración 20260923110000 rellenó esa columna en las tablas dependientes del lead, pero
# su lista dejaba fuera `jabvox_custom_table_rows` —aunque la verificación previa al borrado
# de leads (20260924100000) sí la exige. El resultado era que `drop_jabvox_leads` abortaba
# en producción con miles de filas sin contacto: en la instalación real, 16.326 filas de
# campos personalizados de dos cuentas, todas con su contacto vivo y recuperable.
#
# Va antes del borrado de leads en cualquier instalación nueva y, en las que ya migraron
# hasta aquí, cierra el hueco sin tocar nada más. Idempotente: solo toca filas con
# contact_id NULL, así que reejecutarla no hace nada.
class BackfillCustomTableRowsContactId < ActiveRecord::Migration[7.1]
  def up
    return unless table_exists?(:jabvox_custom_table_rows)
    return unless column_exists?(:jabvox_custom_table_rows, :jabvox_lead_id)
    return unless table_exists?(:jabvox_leads)

    execute(<<~SQL.squish)
      UPDATE jabvox_custom_table_rows r
         SET contact_id = l.contact_id
        FROM jabvox_leads l
       WHERE l.id = r.jabvox_lead_id
         AND r.contact_id IS NULL
    SQL
  end

  # Vaciar la columna de vuelta perdería el único vínculo que quedará cuando se retire
  # jabvox_lead_id, así que no se revierte.
  def down
    raise ActiveRecord::IrreversibleMigration,
          'El relleno de contact_id no se revierte: dejaría las filas sin contacto.'
  end
end
