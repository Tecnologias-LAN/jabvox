# frozen_string_literal: true

# Índices de rendimiento para el dialer (auditoría D-23):
#   - logs abiertos: los consulta el reaper cada minuto y el AMI listener en cada
#     Hangup; sin índice hacían seq scan de una tabla histórica que crece sin fin.
#   - agent_id_jabvox: usado por el fallback por extensión y por el monitor.
# CONCURRENTLY para no bloquear escrituras en producción.
class AddDialerPerformanceIndexes < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    # Índice parcial: casi vacío en régimen sano (solo llamadas en curso).
    add_index :jabvox_dialer_call_logs, %i[account_id started_at_jabvox],
              where: "status_jabvox IN ('initiated', 'calling')",
              name: 'idx_dialer_logs_open_by_account',
              algorithm: :concurrently,
              if_not_exists: true

    add_index :jabvox_dialer_call_logs, :agent_id_jabvox,
              name: 'idx_dialer_logs_on_agent_id',
              algorithm: :concurrently,
              if_not_exists: true

    # Logs abiertos de un agente concreto (monitor / fallback one_by_one).
    add_index :jabvox_dialer_call_logs, %i[agent_id_jabvox ended_at_jabvox],
              name: 'idx_dialer_logs_agent_open',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
