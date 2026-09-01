# frozen_string_literal: true

# Pre-aggregated daily counts for the reports panel. Derived cache over the
# domain source tables; see CreateJabvoxReportDailyRollups. Rebuildable at any
# time by Jabvox::Reports::RollupJob.
# == Schema Information
#
# Table name: jabvox_report_daily_rollups
#
#  id         :bigint           not null, primary key
#  count      :bigint           default(0), not null
#  day        :date             not null
#  metric_key :string           not null
#  sum_value  :decimal(18, 2)   default(0.0), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  inbox_id   :bigint
#  user_id    :bigint
#
# Indexes
#
#  idx_jabvox_report_rollups_bucket  (account_id,metric_key,day,inbox_id,user_id) UNIQUE
#  idx_jabvox_report_rollups_read    (account_id,metric_key,day)
#
class JabvoxReportDailyRollup < ApplicationRecord
  self.table_name = 'jabvox_report_daily_rollups'

  belongs_to :account

  validates :metric_key, :day, presence: true
end
