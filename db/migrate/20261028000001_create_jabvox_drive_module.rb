# Módulo jabvox-drive: almacenamiento privado multiempresa sobre MinIO/S3.
#
# Crea:
#   - Feature flag por cuenta (jabvox_drive_enabled_jabvox).
#   - Carpetas del Drive (jerarquía por metadatos, NO carpetas físicas en MinIO).
#   - Archivos canónicos del Drive (una fila por objeto físico; varias referencias
#     internas comparten la misma fila por sha256 para NO doble-contar la cuota).
#   - Contadores de cuota por cuenta (used/reserved) para reservas atómicas.
#   - Operaciones pendientes (cola de recuperación ante caída de MinIO).
#
# Reversible. No toca datos existentes.
class CreateJabvoxDriveModule < ActiveRecord::Migration[7.1]
  def change
    # --- Feature flag del módulo (gateo backend/frontend) ---
    add_column :accounts, :jabvox_drive_enabled_jabvox, :boolean, default: false, null: false

    # --- Contadores de cuota por cuenta (reserva atómica de espacio) ---
    # used_bytes:     bytes efectivamente almacenados y visibles (bucket principal).
    # reserved_bytes: bytes comprometidos por subidas en vuelo (aún sin confirmar).
    # Se mantienen con UPDATE ... SET x = x + n bajo lock para evitar carreras.
    create_table :jabvox_drive_storage_accounts do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.bigint :used_bytes, null: false, default: 0
      t.bigint :reserved_bytes, null: false, default: 0
      t.bigint :overflow_bytes, null: false, default: 0
      t.datetime :last_reconciled_at
      t.timestamps
    end

    # --- Carpetas (jerarquía lógica por metadatos) ---
    create_table :jabvox_drive_folders do |t|
      t.references :account, null: false, foreign_key: true
      t.references :parent, null: true, foreign_key: { to_table: :jabvox_drive_folders }
      t.references :contact, null: true, foreign_key: true # carpeta canónica de un contacto
      t.string :name, null: false
      # Ruta materializada "/Contactos/123/" para búsqueda/navegación rápida.
      t.string :path, null: false, default: '/'
      # system folders (Contactos, y la de cada contacto) no se pueden borrar/renombrar.
      t.boolean :system_folder, null: false, default: false
      t.references :created_by, null: true, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :jabvox_drive_folders, %i[account_id parent_id name], unique: true,
                                                                    name: 'idx_drive_folders_unique_name'
    add_index :jabvox_drive_folders, %i[account_id contact_id]
    add_index :jabvox_drive_folders, %i[account_id path]

    # --- Archivos canónicos ---
    # bucket:    'primary' | 'overflow' (cuarentena por cuota).
    # object_key: clave completa en MinIO, SIEMPRE prefijada con acct-<id>/.
    # status:    available | restricted (overflow) | pending (subiendo) | quarantined.
    # sha256:    huella del contenido; (account_id, sha256) dedup -> no doble-conteo.
    create_table :jabvox_drive_files do |t|
      t.references :account, null: false, foreign_key: true
      t.references :folder, null: true, foreign_key: { to_table: :jabvox_drive_folders }
      t.references :contact, null: true, foreign_key: true
      t.references :message, null: true, foreign_key: true # origen (adjunto de conversación)
      t.references :conversation, null: true, foreign_key: true
      t.string :filename, null: false
      t.string :content_type
      t.string :bucket, null: false, default: 'primary'
      t.string :object_key, null: false
      t.bigint :byte_size, null: false, default: 0
      t.string :sha256
      t.integer :status, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}
      t.references :created_by, null: true, foreign_key: { to_table: :users }
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :jabvox_drive_files, %i[account_id object_key], unique: true,
                                                              name: 'idx_drive_files_unique_object'
    add_index :jabvox_drive_files, %i[account_id sha256]
    add_index :jabvox_drive_files, %i[account_id contact_id]
    add_index :jabvox_drive_files, %i[account_id message_id]
    add_index :jabvox_drive_files, %i[account_id status]
    add_index :jabvox_drive_files, %i[account_id folder_id]

    # --- Cola de operaciones pendientes (recuperación/idempotencia) ---
    # kind:          ingest_media | move_to_primary | delete_object | reconcile
    # idempotency_key: única -> reintentos seguros, sin duplicar.
    # status:        pending | processing | completed | failed
    create_table :jabvox_drive_pending_operations do |t|
      t.references :account, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :idempotency_key, null: false
      t.integer :status, null: false, default: 0
      t.integer :attempts, null: false, default: 0
      t.jsonb :payload, null: false, default: {}
      t.text :last_error
      t.datetime :next_attempt_at
      t.timestamps
    end
    add_index :jabvox_drive_pending_operations, %i[account_id idempotency_key], unique: true,
                                                                                name: 'idx_drive_pending_unique_key'
    add_index :jabvox_drive_pending_operations, %i[status next_attempt_at]
  end
end
