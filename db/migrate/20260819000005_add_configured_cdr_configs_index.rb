# Índice parcial para que el dispatcher de CDR seleccione en O(log n) solo las
# cuentas con PBX configurado (mysql_host presente), en vez de recorrer todas.
class AddConfiguredCdrConfigsIndex < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :jabvox_cdr_configs, :account_id,
              name: 'idx_cdr_configs_configured',
              where: "mysql_host <> ''",
              algorithm: :concurrently,
              if_not_exists: true
  end
end
