# frozen_string_literal: true

# Configuración global de cuántos días esperar antes de eliminar cuentas que quedaron
# en payment_pending (se registraron pero nunca pagaron). Configurable por super admin.
# == Schema Information
#
# Table name: jabvox_billing_configs
#
#  id                          :bigint           not null, primary key
#  unpaid_account_cleanup_days :integer          default(7), not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#
class JabvoxBillingConfig < ApplicationRecord
  validates :unpaid_account_cleanup_days, presence: true, numericality: { only_integer: true, greater_than: 0 }

  # Singleton: solo existe un registro. Si no existe, devuelve defaults.
  def self.instance
    first_or_create!(unpaid_account_cleanup_days: 7)
  end
end
