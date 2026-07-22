# frozen_string_literal: true

# Cursor de sincronización incremental del CDR: hasta qué calldate ya se ingirió
# en jabvox_cdr_records, para que el job traiga solo lo nuevo del PBX en cada
# corrida (no reprocesa todo el histórico cada minuto).
class AddCdrSyncCursorToConfigs < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_cdr_configs, :last_synced_calldate, :datetime
  end
end
