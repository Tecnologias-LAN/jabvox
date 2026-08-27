# Índice para el orden por defecto del listado de leads (account_id + created_at DESC).
class AddAccountCreatedAtIndexToJabvoxLeads < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :jabvox_leads, %i[account_id created_at],
              name: 'index_jabvox_leads_on_account_id_and_created_at',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
