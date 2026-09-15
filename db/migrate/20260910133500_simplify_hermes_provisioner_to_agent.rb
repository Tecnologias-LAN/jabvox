# frozen_string_literal: true

# El Hermes Aprovisionador global deja de "fabricar un Hermes por cuenta" (2º factor,
# callback webhook, sessions API propia) y pasa a ser UN AGENTE Hermes normal: las cuentas
# ligadas usan ese mismo agente en el Chat Aprovisionador. Por eso:
#   - se quitan las columnas del 2º factor / sessions path (service_user_id, callback_secret,
#     sessions_path), que solo servían al callback del aprovisionador (ya eliminado);
#   - se añade hermes_agent_name_jabvox (el nombre del agente en Hermes, como en las
#     conexiones por cuenta) para completar los 4 campos del agente.
class SimplifyHermesProvisionerToAgent < ActiveRecord::Migration[7.1]
  TABLE = :jabvox_hermes_provisioners
  INDEX = :index_jabvox_hermes_provisioners_on_service_user_id

  def up
    add_column TABLE, :hermes_agent_name_jabvox, :string unless column_exists?(TABLE, :hermes_agent_name_jabvox)

    if column_exists?(TABLE, :service_user_id)
      remove_foreign_key TABLE, column: :service_user_id if foreign_key_exists?(TABLE, column: :service_user_id)
      remove_index TABLE, name: INDEX if index_exists?(TABLE, :service_user_id, name: INDEX)
      remove_column TABLE, :service_user_id
    end
    remove_column TABLE, :callback_secret_jabvox if column_exists?(TABLE, :callback_secret_jabvox)
    remove_column TABLE, :sessions_path_jabvox if column_exists?(TABLE, :sessions_path_jabvox)
  end

  def down
    add_column TABLE, :callback_secret_jabvox, :text unless column_exists?(TABLE, :callback_secret_jabvox)
    column_exists?(TABLE, :sessions_path_jabvox) ||
      add_column(TABLE, :sessions_path_jabvox, :string, default: '/api/sessions', null: false)
    unless column_exists?(TABLE, :service_user_id)
      add_column TABLE, :service_user_id, :bigint
      add_index TABLE, :service_user_id, name: INDEX
      add_foreign_key TABLE, :users, column: :service_user_id
    end
    remove_column TABLE, :hermes_agent_name_jabvox if column_exists?(TABLE, :hermes_agent_name_jabvox)
  end
end
