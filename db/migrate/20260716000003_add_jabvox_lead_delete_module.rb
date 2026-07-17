class AddJabvoxLeadDeleteModule < ActiveRecord::Migration[7.1]
  # Per-account toggle (managed from Super Admin) that controls whether the
  # "delete leads" bulk action is available. Off by default: no account can
  # delete leads until a super admin explicitly enables it. Data-only, additive
  # column — safe to run on production without touching existing rows.
  def change
    add_column :accounts, :jabvox_lead_delete_enabled_jabvox, :boolean, default: false, null: false
  end
end
