# frozen_string_literal: true

# Cursor de sincronización como TEXTO ('YYYY-MM-DD HH:MM:SS'), exactamente como
# Asterisk guarda cdr.calldate. Usar un datetime de ActiveRecord provocaba
# conversiones local<->UTC que desplazaban el cursor y dejaban de traer llamadas
# (cursor pegado). Comparando texto-vs-texto contra el CDR no hay zona horaria de
# por medio. La columna datetime last_synced_calldate se conserva solo para
# mostrar la fecha en el monitor.
class AddCdrSyncCursorTextToConfigs < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_cdr_configs, :last_synced_cursor, :string
  end
end
