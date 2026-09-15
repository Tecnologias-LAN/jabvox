# frozen_string_literal: true

# Sincronización bidireccional con LiteLLM: permite importar TODOS los teams del proxy,
# incluidos los que aún no corresponden a ninguna cuenta de Jabvox ("huérfanos").
#
# Cambios:
#   - account_id pasa a ser OPCIONAL: un team importado de LiteLLM puede existir sin cuenta
#     hasta que un admin lo ligue. El índice único de account_id se vuelve PARCIAL para
#     seguir garantizando "una cuenta ↔ un team" sin bloquear varias filas con NULL.
#   - team_id_jabvox gana un índice único parcial: un mismo team del proxy no puede
#     importarse dos veces.
#   - Campos espejo de LiteLLM (alias, max_budget, blocked, modelos) para mostrar en la UI
#     lo que realmente hay en el proxy y detectar divergencias sin llamar en cada render.
class AddLitellmSyncToAiProviderAccounts < ActiveRecord::Migration[7.1]
  def up
    # --- account_id opcional (teams huérfanos importados del proxy) ---
    change_column_null :jabvox_ai_provider_accounts, :account_id, true

    remove_index :jabvox_ai_provider_accounts, :account_id
    add_index :jabvox_ai_provider_accounts, :account_id, unique: true,
                                                         where: 'account_id IS NOT NULL',
                                                         name: 'idx_ai_provider_accounts_account'

    # --- un team del proxy no puede estar ligado dos veces ---
    remove_index :jabvox_ai_provider_accounts, :team_id_jabvox
    add_index :jabvox_ai_provider_accounts, :team_id_jabvox, unique: true,
                                                             where: "team_id_jabvox IS NOT NULL AND team_id_jabvox <> ''",
                                                             name: 'idx_ai_provider_accounts_team'

    # --- espejo de lo que hay en LiteLLM (para la UI y para detectar divergencias) ---
    add_column :jabvox_ai_provider_accounts, :team_alias_jabvox, :string
    # max_budget tal como lo reporta el proxy. NULL = sin tope en el proxy.
    add_column :jabvox_ai_provider_accounts, :remote_max_budget_jabvox, :decimal, precision: 15, scale: 6
    add_column :jabvox_ai_provider_accounts, :remote_blocked_jabvox, :boolean, null: false, default: false
    add_column :jabvox_ai_provider_accounts, :remote_models_jabvox, :jsonb, null: false, default: []
    # De dónde salió la fila: 'jabvox' (creada aquí) o 'litellm' (importada del proxy).
    add_column :jabvox_ai_provider_accounts, :origin_jabvox, :string, null: false, default: 'jabvox'
  end

  def down
    remove_column :jabvox_ai_provider_accounts, :origin_jabvox
    remove_column :jabvox_ai_provider_accounts, :remote_models_jabvox
    remove_column :jabvox_ai_provider_accounts, :remote_blocked_jabvox
    remove_column :jabvox_ai_provider_accounts, :remote_max_budget_jabvox
    remove_column :jabvox_ai_provider_accounts, :team_alias_jabvox

    remove_index :jabvox_ai_provider_accounts, name: 'idx_ai_provider_accounts_team'
    add_index :jabvox_ai_provider_accounts, :team_id_jabvox

    remove_index :jabvox_ai_provider_accounts, name: 'idx_ai_provider_accounts_account'
    # Volver a NOT NULL exige que no queden filas huérfanas.
    execute 'DELETE FROM jabvox_ai_provider_accounts WHERE account_id IS NULL'
    change_column_null :jabvox_ai_provider_accounts, :account_id, false
    add_index :jabvox_ai_provider_accounts, :account_id, unique: true
  end
end
