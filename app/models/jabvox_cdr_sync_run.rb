# frozen_string_literal: true

# Auditoría de una ejecución del sincronizador de CDR (ver CreateJabvoxCdrSyncRuns).
# == Schema Information
#
# Table name: jabvox_cdr_sync_runs
#
#  id             :bigint           not null, primary key
#  cursor_after   :datetime
#  cursor_before  :datetime
#  duration_ms    :integer          default(0)
#  error_count    :integer          default(0), not null
#  error_message  :text
#  fetched_count  :integer          default(0), not null
#  finished_at    :datetime
#  inserted_count :integer          default(0), not null
#  pbx_reachable  :boolean          default(FALSE), not null
#  skipped_count  :integer          default(0), not null
#  started_at     :datetime         not null
#  status         :string           default("ok"), not null
#  updated_count  :integer          default(0), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#
# Indexes
#
#  idx_cdr_sync_runs_account_started         (account_id,started_at)
#  index_jabvox_cdr_sync_runs_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxCdrSyncRun < ApplicationRecord
  self.table_name = 'jabvox_cdr_sync_runs'

  belongs_to :account

  STATUSES = %w[ok unreachable error skipped].freeze

  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :recent_first, -> { order(started_at: :desc) }
end
