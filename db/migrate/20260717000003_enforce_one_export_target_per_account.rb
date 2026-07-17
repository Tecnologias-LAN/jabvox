class EnforceOneExportTargetPerAccount < ActiveRecord::Migration[7.1]
  # Golden rule at the DB level: exactly one external export DB per account.
  # A unique index on account_id makes concurrent creates race-safe (the second
  # INSERT fails with RecordNotUnique instead of silently creating a second one).
  #
  # Guarded: if any account already has 2+ targets (shouldn't happen), keep only
  # the oldest so the unique index can be created without error.
  def up
    dedupe_existing!
    add_index :jabvox_export_targets, :account_id, unique: true,
              name: 'idx_export_targets_one_per_account'
  end

  def down
    remove_index :jabvox_export_targets, name: 'idx_export_targets_one_per_account'
  end

  private

  def dedupe_existing!
    dupes = execute(<<~SQL).to_a
      SELECT account_id FROM jabvox_export_targets
      GROUP BY account_id HAVING COUNT(*) > 1
    SQL
    dupes.each do |row|
      account_id = row['account_id']
      keep = execute("SELECT id FROM jabvox_export_targets WHERE account_id = #{account_id.to_i} ORDER BY id ASC LIMIT 1").first['id']
      execute("DELETE FROM jabvox_export_targets WHERE account_id = #{account_id.to_i} AND id <> #{keep.to_i}")
    end
  end
end
