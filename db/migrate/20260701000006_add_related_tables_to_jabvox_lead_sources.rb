# Stores the configuration of related external tables to LEFT JOIN into the main
# lead table during import (e.g. leads + leads_facturacion + leads_csmt).
# Shape: [{ "table" => "leads_facturacion", "local_key" => "id",
#           "foreign_key" => "lead_id", "alias" => "fact" }, ...]
class AddRelatedTablesToJabvoxLeadSources < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_lead_sources, :related_tables_jabvox, :jsonb, null: false, default: []
  end
end
