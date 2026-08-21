# frozen_string_literal: true

class AddPaymentPendingStatusToAccounts < ActiveRecord::Migration[7.0]
  def up
    # Agregar payment_pending = 2 al enum status de accounts
    # No requiere cambios en la columna, solo en el modelo
  end

  def down
    # No-op: el enum se maneja en el modelo
  end
end
