class CreateJabvoxExportSyncLogs < ActiveRecord::Migration[7.1]
  # History of export attempts so the settings screen can show what was sent,
  # what is queued/retrying, and what failed. One row per (target, model,
  # record) keyed uniquely so retries UPDATE instead of piling up — the table
  # stays bounded to the number of distinct records, not the number of attempts.
  def change
    create_table :jabvox_export_sync_logs do |t|
      t.references :account, null: false, foreign_key: true
      t.references :jabvox_export_target, null: false, foreign_key: true
      t.string :model_name_jabvox, null: false
      t.bigint :record_id_jabvox, null: false
      t.string :status_jabvox, null: false, default: 'queued' # queued | exported | failed
      t.string :operation_jabvox, null: false, default: 'realtime' # realtime | backfill
      t.string :error_jabvox
      t.integer :attempts_jabvox, null: false, default: 0
      t.datetime :last_attempt_at_jabvox
      t.datetime :exported_at_jabvox
      t.timestamps
    end

    add_index :jabvox_export_sync_logs,
              %i[jabvox_export_target_id model_name_jabvox record_id_jabvox],
              unique: true, name: 'idx_export_sync_logs_unique_record'
    add_index :jabvox_export_sync_logs, %i[account_id status_jabvox]
    add_index :jabvox_export_sync_logs, %i[jabvox_export_target_id status_jabvox last_attempt_at_jabvox],
              name: 'idx_export_sync_logs_target_status'
  end
end
