class AddLeadNumberToJabvoxLeads < ActiveRecord::Migration[7.1]
  def up
    add_column :jabvox_leads, :lead_number, :integer

    # Backfill existing leads with sequential numbers per account
    execute <<~SQL
      UPDATE jabvox_leads jl
      SET lead_number = sub.row_num
      FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY account_id ORDER BY created_at ASC) AS row_num
        FROM jabvox_leads
      ) sub
      WHERE jl.id = sub.id
    SQL

    change_column_null :jabvox_leads, :lead_number, false
    add_index :jabvox_leads, %i[account_id lead_number], unique: true
  end

  def down
    remove_index :jabvox_leads, %i[account_id lead_number]
    remove_column :jabvox_leads, :lead_number
  end
end
