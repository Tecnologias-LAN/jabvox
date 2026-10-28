# Activa el módulo de Empresas (feature `companies`) en las cuentas ya existentes.
#
# Para cuentas NUEVAS no hace falta tocar nada aquí: `companies` quedó con
# `enabled: true` en config/features.yml y ConfigLoader actualiza
# ACCOUNT_LEVEL_FEATURE_DEFAULTS en el deploy, igual que captain_tasks
# (ver 20260120121402_enable_captain_tasks_for_existing_accounts.rb).
#
# Esta migración solo cubre las cuentas que ya existían antes del cambio, que no
# heredan el nuevo default. Es idempotente: `enable_features!` sobre una cuenta que
# ya lo tiene no cambia nada.
class EnableCompaniesForExistingAccounts < ActiveRecord::Migration[7.1]
  def up
    Account.find_in_batches(batch_size: 100) do |accounts|
      accounts.each { |account| account.enable_features!('companies') }
    end
  end

  def down
    Account.find_in_batches(batch_size: 100) do |accounts|
      accounts.each { |account| account.disable_features!('companies') }
    end
  end
end
