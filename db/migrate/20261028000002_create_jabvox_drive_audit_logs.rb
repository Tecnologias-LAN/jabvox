# Bitácora de auditoría del Drive (append-only): registra QUIÉN hizo QUÉ sobre cada
# archivo/carpeta — crear, subir, descargar, renombrar, mover, eliminar, crear carpeta,
# regularizar, etc. Metadatos saneados (nunca contenido ni URLs firmadas). Reversible.
class CreateJabvoxDriveAuditLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_drive_audit_logs do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true # quién (nil = sistema/job)
      t.string :action, null: false        # upload, download, rename, move, delete, create_folder, ...
      t.string :result, null: false, default: 'success' # success | failure | rejected
      t.string :auditable_type             # JabvoxDriveFile | JabvoxDriveFolder
      t.bigint :auditable_id
      t.string :ip_address
      t.string :user_agent
      t.jsonb :metadata, null: false, default: {}
      # Sin updated_at: append-only. created_at manual.
      t.datetime :created_at, null: false
    end

    add_index :jabvox_drive_audit_logs, %i[account_id created_at]
    add_index :jabvox_drive_audit_logs, %i[account_id action]
    add_index :jabvox_drive_audit_logs, %i[account_id auditable_type auditable_id],
              name: 'idx_drive_audit_auditable'
    # (el índice de user_id lo crea t.references :user)
  end
end
