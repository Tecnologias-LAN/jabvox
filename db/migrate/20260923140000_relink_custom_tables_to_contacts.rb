# frozen_string_literal: true

# Las tablas personalizadas se vinculaban a 'leads'; con la unificación pasan a 'contacts'.
#
# `linked_to_jabvox` es lo que decide si una tabla personalizada aporta campos a la ficha
# (una fila por registro) o es una tabla suelta. Si se dejara en 'leads', los campos
# personalizados dejarían de aparecer en el contacto al retirar la pantalla de Leads.
#
# También se renombra la tabla llamada literalmente "Leads", que es el nombre que ve el
# usuario en Personalización.
class RelinkCustomTablesToContacts < ActiveRecord::Migration[7.1]
  def up
    return unless table_exists?(:jabvox_custom_tables)

    execute("UPDATE jabvox_custom_tables SET linked_to_jabvox = 'contacts' WHERE linked_to_jabvox = 'leads'")
    # Solo si conserva el nombre por defecto: si el usuario la renombró, se respeta.
    execute(<<~SQL.squish)
      UPDATE jabvox_custom_tables
         SET name_jabvox = 'Contactos'
       WHERE linked_to_jabvox = 'contacts' AND name_jabvox IN ('Leads', 'leads')
    SQL
  end

  def down
    return unless table_exists?(:jabvox_custom_tables)

    execute("UPDATE jabvox_custom_tables SET linked_to_jabvox = 'leads' WHERE linked_to_jabvox = 'contacts'")
    execute("UPDATE jabvox_custom_tables SET name_jabvox = 'Leads' WHERE name_jabvox = 'Contactos'")
  end
end
