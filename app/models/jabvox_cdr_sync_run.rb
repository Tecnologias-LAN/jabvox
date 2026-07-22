# frozen_string_literal: true

# Auditoría de una ejecución del sincronizador de CDR (ver CreateJabvoxCdrSyncRuns).
class JabvoxCdrSyncRun < ApplicationRecord
  self.table_name = 'jabvox_cdr_sync_runs'

  belongs_to :account

  STATUSES = %w[ok unreachable error skipped].freeze

  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :recent_first, -> { order(started_at: :desc) }
end
