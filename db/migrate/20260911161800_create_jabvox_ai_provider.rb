# frozen_string_literal: true

# Integración con el proveedor de API de IA (proxy tipo LiteLLM, GENÉRICO y configurable).
# Modelo de saldos por cuenta ligado a planes:
#   - jabvox_ai_provider_configs   : singleton global (base_url + master_key cifrada + estado).
#   - jabvox_ai_provider_accounts  : mapeo cuenta ↔ team del proveedor + desglose de saldo
#                                    (saldo del plan mensual + saldo comprado que se acumula).
#   - jabvox_ai_balance_movements  : historial append-only de TODO movimiento de saldo
#                                    (reset mensual, recarga comprada, ajuste) con idempotencia.
class CreateJabvoxAiProvider < ActiveRecord::Migration[7.1]
  def change
    # --- Config global del proveedor (singleton) ---
    create_table :jabvox_ai_provider_configs do |t|
      t.string   :provider_name_jabvox, null: false, default: 'Proveedor IA'
      t.string   :base_url_jabvox
      t.text     :master_key_jabvox                 # CIFRADA. Nunca sale al frontend.
      t.boolean  :enabled_jabvox, null: false, default: false
      t.string   :status_jabvox, null: false, default: 'disconnected' # disconnected|connected|error
      t.datetime :last_check_at_jabvox
      t.string   :last_error_jabvox
      t.timestamps
    end

    # --- Mapeo cuenta ↔ proveedor + desglose de saldo ---
    create_table :jabvox_ai_provider_accounts do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.string   :team_id_jabvox                    # id del team en el proveedor
      # Desglose del saldo (en centavos de USD para evitar flotantes):
      #   plan_budget_cents      → lo que da el plan; se RESTABLECE cada mes.
      #   purchased_budget_cents → comprado aparte; se ACUMULA (no se restablece).
      # El tope enviado al proveedor (max_budget) = (plan + purchased) / 100.0
      t.integer  :plan_budget_cents_jabvox, null: false, default: 0
      t.integer  :purchased_budget_cents_jabvox, null: false, default: 0
      # Gasto cacheado leído del proveedor (spend), para no llamar en cada vista.
      t.decimal  :cached_spend_jabvox, precision: 15, scale: 6
      t.datetime :spend_updated_at_jabvox
      # Marca del último restablecimiento mensual, para no restablecer dos veces el mismo mes.
      t.string   :last_reset_period_jabvox          # 'YYYY-MM'
      t.string   :status_jabvox, null: false, default: 'active' # active|blocked
      t.datetime :synced_at_jabvox                  # última sincronización con el proveedor
      t.string   :last_error_jabvox
      t.timestamps
    end
    add_index :jabvox_ai_provider_accounts, :team_id_jabvox

    # --- Historial append-only de movimientos de saldo ---
    create_table :jabvox_ai_balance_movements do |t|
      t.references :account, null: false, foreign_key: true
      t.string   :kind_jabvox, null: false          # plan_reset|purchase|adjustment|plan_assign
      t.integer  :amount_cents_jabvox, null: false, default: 0 # delta aplicado (+/-)
      t.integer  :plan_budget_cents_after_jabvox               # foto del saldo tras el movimiento
      t.integer  :purchased_budget_cents_after_jabvox
      t.bigint   :jabvox_plan_id                    # plan implicado, si aplica
      t.string   :reference_jabvox                  # id de transacción/pago, si aplica
      t.string   :idempotency_key_jabvox            # evita aplicar dos veces el mismo movimiento
      t.jsonb    :metadata_jabvox, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :jabvox_ai_balance_movements, %i[account_id created_at],
              name: 'idx_ai_balance_movements_account'
    # Idempotencia dura: una clave sólo puede registrarse una vez (donde exista).
    add_index :jabvox_ai_balance_movements, :idempotency_key_jabvox, unique: true,
                                                                     where: 'idempotency_key_jabvox IS NOT NULL',
                                                                     name: 'idx_ai_balance_movements_idem'
  end
end
