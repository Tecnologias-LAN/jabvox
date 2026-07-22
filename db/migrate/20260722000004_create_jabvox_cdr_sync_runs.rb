# frozen_string_literal: true

# Trazabilidad (auditoría) de cada ejecución del sincronizador de CDR por cuenta.
# El dashboard de monitoreo lee de aquí: última corrida, duración, cuántos se
# sincronizaron/omitieron/duplicaron, errores, tiempo promedio, cursor, estado
# del PBX. Una fila por corrida y cuenta.
class CreateJabvoxCdrSyncRuns < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_cdr_sync_runs do |t|
      t.references :account, null: false, foreign_key: true

      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.integer  :duration_ms, default: 0        # cuánto tardó la corrida
      t.boolean  :pbx_reachable, default: false, null: false

      t.integer  :inserted_count, default: 0, null: false
      t.integer  :updated_count,  default: 0, null: false
      t.integer  :skipped_count,  default: 0, null: false  # filas sin uniqueid, etc.
      t.integer  :error_count,    default: 0, null: false
      t.integer  :fetched_count,  default: 0, null: false  # filas traídas del PBX

      t.datetime :cursor_before                 # cursor al iniciar
      t.datetime :cursor_after                  # cursor tras la corrida
      t.string   :status, default: 'ok', null: false # ok | unreachable | error | skipped
      t.text     :error_message                 # primer error, si hubo

      t.timestamps
    end

    add_index :jabvox_cdr_sync_runs, %i[account_id started_at],
              name: 'idx_cdr_sync_runs_account_started'
  end
end
