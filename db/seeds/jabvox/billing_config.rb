# frozen_string_literal: true

# Configurable desde super_admin: tiempo de espera antes de eliminar cuentas
# que se registraron pero nunca pagaron (suspended + sin transacción aprobada).
InstallationConfig.find_or_create_by!(name: 'JABVOX_PENDING_PAYMENT_CLEANUP_HOURS') do |config|
  config.value = 48
  config.locked = false
end
