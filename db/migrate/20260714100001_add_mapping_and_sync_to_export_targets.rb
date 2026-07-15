# Adds the "map to an existing DB" mode plus periodic-sync bookkeeping to the
# external data-export target.
#
# mode_jabvox: 'create' (build our own tables — current behavior) or 'map'
#   (write only into columns that already exist in the customer's DB).
# field_mapping_jabvox: per-table mapping, shape:
#   { "jabvox_leads": { "key": "<customer_key_col>",
#                       "columns": { "<jabvox_col>": "<customer_col>", ... } }, ... }
# create_missing_columns_jabvox: in map mode, whether Jabvox may ALTER TABLE to
#   add mapped columns that don't exist yet (DDL, opt-in).
# last_full_sync_at_jabvox / last_sync_result_jabvox / sync_status_jabvox: the
#   backfill + 5-minute reconciliation watermark, counters and state (mirrors
#   JabvoxLeadSource's sync bookkeeping).
class AddMappingAndSyncToExportTargets < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_export_targets, :mode_jabvox, :string, default: 'create', null: false
    add_column :jabvox_export_targets, :field_mapping_jabvox, :jsonb, default: {}, null: false
    add_column :jabvox_export_targets, :create_missing_columns_jabvox, :boolean, default: false, null: false
    add_column :jabvox_export_targets, :last_full_sync_at_jabvox, :datetime
    add_column :jabvox_export_targets, :last_sync_result_jabvox, :jsonb, default: {}, null: false
    add_column :jabvox_export_targets, :sync_status_jabvox, :string, default: 'idle', null: false
  end
end
