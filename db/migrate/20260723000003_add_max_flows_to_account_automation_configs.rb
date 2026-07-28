# frozen_string_literal: true

# Límite de flujos por cuenta en la plataforma Automations.
# NULL = ilimitado. Se envía al backend al aprovisionar/actualizar el módulo.
class AddMaxFlowsToAccountAutomationConfigs < ActiveRecord::Migration[7.1]
  def change
    add_column :account_automation_configs, :max_flows, :integer, null: true
  end
end
