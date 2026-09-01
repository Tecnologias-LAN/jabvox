# frozen_string_literal: true

# Pre-aggregated daily counts for the Jabvox reports panel.
#
# One row per (account, metric, day, inbox, agent). The summary reads closed
# days from here and only queries the source tables live for the day in
# progress, so the KPI cards stay fast even at millions of source rows.
#
# The rollup is populated by Jabvox::Reports::RollupJob (nightly + incremental).
# It is a derived cache: it can always be rebuilt from the source tables, so it
# carries no foreign keys and is safe to truncate/recompute.
class CreateJabvoxReportDailyRollups < ActiveRecord::Migration[7.1]
  def change
    return if table_exists?(:jabvox_report_daily_rollups)

    create_table :jabvox_report_daily_rollups do |t|
      t.bigint :account_id, null: false
      t.string :metric_key, null: false          # messages_sent, calls, orders, ...
      t.date :day, null: false                   # day in the account timezone
      t.bigint :inbox_id                          # nullable: not every metric has an inbox
      t.bigint :user_id                           # agent the row is attributed to (nullable)
      t.bigint :count, null: false, default: 0
      t.decimal :sum_value, precision: 18, scale: 2, null: false, default: 0 # e.g. order totals, call seconds

      t.timestamps
    end

    # One row per bucket; the job upserts on this key.
    add_index :jabvox_report_daily_rollups,
              %i[account_id metric_key day inbox_id user_id],
              unique: true,
              name: 'idx_jabvox_report_rollups_bucket'
    # Primary read path for the summary: account + metric + day range.
    add_index :jabvox_report_daily_rollups,
              %i[account_id metric_key day],
              name: 'idx_jabvox_report_rollups_read'
  end
end
