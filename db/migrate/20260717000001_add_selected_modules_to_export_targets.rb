class AddSelectedModulesToExportTargets < ActiveRecord::Migration[7.1]
  # Which module groups the customer chose to export (empty = all enabled modules).
  # Stored as a jsonb array of module keys (e.g. ["leads","conversations","dialer"]).
  # Additive + defaulted, so it's safe on production without touching existing rows.
  def change
    add_column :jabvox_export_targets, :selected_modules_jabvox, :jsonb, default: [], null: false
  end
end
