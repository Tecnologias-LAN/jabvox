# frozen_string_literal: true

# Feature flag por cuenta para el módulo "Automatizaciones Avanzadas".
# Sigue el patrón del resto de columnas jabvox_*_enabled_jabvox.
class AddAdvancedAutomationsToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :jabvox_advanced_automations_enabled_jabvox, :boolean, default: false, null: false
  end
end
