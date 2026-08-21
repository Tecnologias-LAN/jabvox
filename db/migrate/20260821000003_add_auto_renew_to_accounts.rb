# frozen_string_literal: true

# Preferencia de renovación automática por cuenta. HOY Bold NO permite cobros automáticos
# (no tokeniza tarjetas), así que este flag NO dispara cobros por sí solo: queda como
# preferencia del cliente y base para una futura integración con tokenización/suscripción.
# Mientras tanto, la renovación es por recordatorio + pago manual.
class AddAutoRenewToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :jabvox_auto_renew, :boolean, null: false, default: false
  end
end
