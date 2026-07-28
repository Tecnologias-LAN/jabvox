# frozen_string_literal: true

# Selector de usuario para las automatizaciones + máquina de estados por cuenta.
# Sustituye al usuario de servicio que se creaba solo al activar el módulo.
class AddAutomationsUserToAccountAutomationConfigs < ActiveRecord::Migration[7.1]
  def up
    # FK a `users` (no a `account_users`) porque el access token es polimórfico sobre
    # el owner. ON DELETE SET NULL: borrar al User deja la cuenta en pendiente_token.
    add_reference :account_automation_configs, :automations_user,
                  foreign_key: { to_table: :users, on_delete: :nullify },
                  index: true, null: true

    # Columna nueva en vez de reciclar `last_status`: esa string es el diagnóstico de
    # la última llamada remota, esto es el ciclo de vida. Entero, como AccountUser#role.
    add_column :account_automation_configs, :automations_state, :integer, default: 0, null: false

    # Rastro de auditoría en la propia fila, independiente de la gema `audited`.
    # `set_by_id` sin FK a propósito: un registro histórico no debe borrarse en cascada.
    add_column :account_automation_configs, :automations_user_set_at, :datetime, null: true
    add_column :account_automation_configs, :automations_user_set_by_id, :bigint, null: true
    add_column :account_automation_configs, :automations_user_set_ip, :string, null: true
  end

  def down
    remove_column :account_automation_configs, :automations_user_set_ip
    remove_column :account_automation_configs, :automations_user_set_by_id
    remove_column :account_automation_configs, :automations_user_set_at
    remove_column :account_automation_configs, :automations_state
    remove_reference :account_automation_configs, :automations_user,
                     foreign_key: { to_table: :users }, index: true
  end
end
