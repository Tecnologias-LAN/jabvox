# frozen_string_literal: true

# Tabla LOCAL que materializa el CDR del PBX (asteriskcdrdb) enriquecido con los
# datos de Jabvox (número real del dialer, medio, agente, tipificación). Un job
# la sincroniza incrementalmente. El reporte lee de aquí en vez de consultar el
# MySQL externo, para poder FILTRAR y PAGINAR de forma exacta a cualquier volumen
# (con dos bases separadas no se podía hacer WHERE+COUNT sobre datos enriquecidos).
#
# NO cambia el dialer ni el click-to-call: es solo materialización de reportes.
class CreateJabvoxCdrRecords < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_cdr_records do |t|
      t.references :account, null: false, foreign_key: true

      # --- Crudas del CDR del PBX (fuente para enrichment y trazabilidad) ---
      t.string   :uniqueid, null: false
      t.string   :linkedid
      t.datetime :calldate, null: false
      t.string   :src
      t.string   :dst
      t.string   :channel
      t.string   :dstchannel
      t.string   :disposition
      t.integer  :duration, default: 0
      t.integer  :billsec, default: 0
      t.string   :recordingfile

      # --- Enriquecidas (ya resueltas en la ingesta; lo que muestra el reporte) ---
      t.string  :origin           # nombre del agente / número real / src
      t.string  :destination      # número real marcado (no 's')
      t.string  :origin_channel   # etiqueta del agente
      t.string  :agent_extension  # extensión del agente (para filtro por ext/rango)
      t.string  :medium           # dialer | click_to_call | manual
      t.string  :agent_name
      t.bigint  :typification_id
      t.string  :typification

      t.timestamps
    end

    # uniqueid es único por cuenta (idempotencia de la ingesta).
    add_index :jabvox_cdr_records, %i[account_id uniqueid], unique: true,
                                                            name: 'idx_cdr_records_account_uniqueid'
    # Orden/paginación principal del reporte (calldate DESC) por cuenta.
    add_index :jabvox_cdr_records, %i[account_id calldate],
              name: 'idx_cdr_records_account_calldate'
    # Filtros frecuentes.
    add_index :jabvox_cdr_records, %i[account_id agent_extension],
              name: 'idx_cdr_records_account_agent_ext'
    add_index :jabvox_cdr_records, %i[account_id medium],
              name: 'idx_cdr_records_account_medium'
    add_index :jabvox_cdr_records, %i[account_id disposition],
              name: 'idx_cdr_records_account_disposition'
    add_index :jabvox_cdr_records, %i[account_id typification_id],
              name: 'idx_cdr_records_account_typ'
  end
end
