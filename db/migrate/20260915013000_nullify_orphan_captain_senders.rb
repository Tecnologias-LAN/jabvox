# DropCaptainTables borró las tablas del módulo Captain, pero los mensajes que ese
# asistente había enviado conservaron `sender_type = 'Captain::Assistant'`. Como la clase
# ya no existe, cargar cualquiera de esos mensajes revienta la asociación polimórfica
# `Message#sender` con `NameError: uninitialized constant Captain` — y con ella el listado
# de mensajes y de conversaciones de toda la cuenta.
#
# `sender` es `optional: true`, así que dejar el sender en NULL conserva el mensaje (su
# contenido, fecha y tipo siguen intactos) y solo lo desliga del remitente inexistente.
class NullifyOrphanCaptainSenders < ActiveRecord::Migration[7.1]
  def up
    execute(<<~SQL.squish)
      UPDATE messages
      SET sender_type = NULL, sender_id = NULL
      WHERE sender_type LIKE 'Captain::%'
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
