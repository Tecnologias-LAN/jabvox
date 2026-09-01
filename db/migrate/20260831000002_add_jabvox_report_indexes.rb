# frozen_string_literal: true

# Indexes that back the live (day-in-progress) and drill-down keyset queries of
# the reports module. Every drill-down paginates by (created_at DESC, id DESC)
# scoped to an account, so each source table needs a matching composite index.
# Added CONCURRENTLY so this is safe to run on a live production table.
class AddJabvoxReportIndexes < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    # Orders drill-down + live count (had only single-column account_id).
    add_index :jabvox_orders, %i[account_id created_at id],
              order: { created_at: :desc, id: :desc },
              name: 'idx_jabvox_orders_account_created_keyset',
              algorithm: :concurrently, if_not_exists: true

    # Management answers drill-down + live count.
    add_index :jabvox_management_answers, %i[account_id created_at id],
              order: { created_at: :desc, id: :desc },
              name: 'idx_jabvox_mgmt_answers_account_created_keyset',
              algorithm: :concurrently, if_not_exists: true

    # Label logs: puestas keyed by applied_at, quitadas by removed_at.
    add_index :jabvox_conversation_label_logs, %i[account_id applied_at_jabvox id],
              order: { applied_at_jabvox: :desc, id: :desc },
              name: 'idx_conv_label_logs_account_applied_keyset',
              algorithm: :concurrently, if_not_exists: true
    add_index :jabvox_conversation_label_logs, %i[account_id removed_at_jabvox id],
              order: { removed_at_jabvox: :desc, id: :desc },
              name: 'idx_conv_label_logs_account_removed_keyset',
              algorithm: :concurrently, if_not_exists: true

    # CDR already has (account_id, calldate); add id tiebreaker for stable keyset.
    add_index :jabvox_cdr_records, %i[account_id calldate id],
              order: { calldate: :desc, id: :desc },
              name: 'idx_cdr_records_account_calldate_keyset',
              algorithm: :concurrently, if_not_exists: true
  end
end
