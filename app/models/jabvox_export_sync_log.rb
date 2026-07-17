# One row per (target, model, record) tracking its export state, so the settings
# screen can show a live history: exported, queued/retrying, or failed. Retries
# update the same row (upsert on the unique index), keeping the table bounded to
# the number of distinct records rather than every attempt.
# == Schema Information
#
# Table name: jabvox_export_sync_logs
#
#  id                      :bigint           not null, primary key
#  attempts_jabvox         :integer          default(0), not null
#  error_jabvox            :string
#  exported_at_jabvox      :datetime
#  last_attempt_at_jabvox  :datetime
#  model_name_jabvox       :string           not null
#  operation_jabvox        :string           default("realtime"), not null
#  record_id_jabvox        :bigint           not null
#  status_jabvox           :string           default("queued"), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint           not null
#  jabvox_export_target_id :bigint           not null
#
# Indexes
#
#  idx_export_sync_logs_target_status                             (jabvox_export_target_id,status_jabvox,last_attempt_at_jabvox)
#  idx_export_sync_logs_unique_record                             (jabvox_export_target_id,model_name_jabvox,record_id_jabvox) UNIQUE
#  index_jabvox_export_sync_logs_on_account_id                    (account_id)
#  index_jabvox_export_sync_logs_on_account_id_and_status_jabvox  (account_id,status_jabvox)
#  index_jabvox_export_sync_logs_on_jabvox_export_target_id       (jabvox_export_target_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (jabvox_export_target_id => jabvox_export_targets.id)
#
class JabvoxExportSyncLog < ApplicationRecord
  self.table_name = 'jabvox_export_sync_logs'

  STATUSES = %w[queued exported failed].freeze

  belongs_to :account
  belongs_to :jabvox_export_target

  validates :model_name_jabvox, presence: true
  validates :record_id_jabvox, presence: true
  validates :status_jabvox, inclusion: { in: STATUSES }

  scope :recent_first, -> { order(last_attempt_at_jabvox: :desc, updated_at: :desc) }
  scope :with_status, ->(s) { where(status_jabvox: s) if s.present? }

  # Upserts the state for one record without loading it first: a single INSERT ..
  # ON CONFLICT keeps the real-time write path cheap and race-free under
  # concurrency (many jobs touching the same record).
  def self.record!(target:, model_name:, record_id:, status:, operation:, error: nil)
    now = Time.current
    exported_at = status == 'exported' ? now : nil
    upsert(
      {
        account_id: target.account_id,
        jabvox_export_target_id: target.id,
        model_name_jabvox: model_name,
        record_id_jabvox: record_id,
        status_jabvox: status,
        operation_jabvox: operation,
        error_jabvox: error&.slice(0, 500),
        attempts_jabvox: 1,
        last_attempt_at_jabvox: now,
        exported_at_jabvox: exported_at,
        created_at: now,
        updated_at: now
      },
      unique_by: :idx_export_sync_logs_unique_record,
      on_duplicate: Arel.sql(
        'status_jabvox = EXCLUDED.status_jabvox, ' \
        'operation_jabvox = EXCLUDED.operation_jabvox, ' \
        'error_jabvox = EXCLUDED.error_jabvox, ' \
        'attempts_jabvox = jabvox_export_sync_logs.attempts_jabvox + 1, ' \
        'last_attempt_at_jabvox = EXCLUDED.last_attempt_at_jabvox, ' \
        'exported_at_jabvox = COALESCE(EXCLUDED.exported_at_jabvox, jabvox_export_sync_logs.exported_at_jabvox), ' \
        'updated_at = EXCLUDED.updated_at'
      )
    )
  rescue StandardError => e
    # History is best-effort telemetry; never let it break the export itself.
    Rails.logger.error("[ExportSyncLog] record! failed: #{e.class}: #{e.message}")
  end

  # Aggregate counters for the target (for the history header). Scoped by both
  # account and target as defense-in-depth against a mis-scoped caller.
  def self.counts_for(target)
    where(account_id: target.account_id, jabvox_export_target_id: target.id)
      .group(:status_jabvox).count
  end
end
