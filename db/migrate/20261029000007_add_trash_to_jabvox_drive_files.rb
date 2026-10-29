# Papelera del jabvox-drive. `deleted_at` ya existía (envío a papelera = soft delete);
# aquí se añade:
#   purged_at:      cuándo se borró DEFINITIVAMENTE (objeto físico fuera + cuota liberada).
#                   deleted_at != nil && purged_at == nil  => está EN la papelera (ocupa cuota).
#                   purged_at != nil                        => eliminado del todo (ya no ocupa).
#   trashed_by_id:  quién lo mandó a la papelera (para el historial).
#   purged_by_id:   quién lo eliminó permanentemente (para el historial).
#
# Reversible. No toca datos existentes (todas nullable).
class AddTrashToJabvoxDriveFiles < ActiveRecord::Migration[7.1]
  def change
    change_table :jabvox_drive_files, bulk: true do |t|
      t.datetime :purged_at
      t.bigint :trashed_by_id
      t.bigint :purged_by_id
    end

    # Índice para el barrido de la papelera (los que llevan >7 días en papelera).
    add_index :jabvox_drive_files, [:account_id, :deleted_at],
              where: 'deleted_at IS NOT NULL AND purged_at IS NULL',
              name: 'idx_drive_files_in_trash'
  end
end
