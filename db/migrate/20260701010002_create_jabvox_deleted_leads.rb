# Trash for leads removed together with a lead-import connection. Each row holds a
# full snapshot of the lead (+ contact + custom fields) so it can be restored from
# super admin within the retention window (20 days); a scheduled job purges older.
class CreateJabvoxDeletedLeads < ActiveRecord::Migration[7.1]
  def change
    create_table :jabvox_deleted_leads do |t|
      t.references :account, null: false, foreign_key: true
      t.bigint :original_lead_id_jabvox         # the lead id it had before deletion
      t.string :source_name_jabvox               # which connection removed it
      t.string :external_id_jabvox               # external id it was linked to
      t.jsonb :snapshot_jabvox, null: false, default: {} # full lead+contact payload
      t.datetime :deleted_at_jabvox, null: false
      t.references :deleted_by, foreign_key: { to_table: :users }, null: true
      t.datetime :restored_at_jabvox             # set when restored
      t.timestamps
      t.index %i[account_id deleted_at_jabvox]
    end
  end
end
