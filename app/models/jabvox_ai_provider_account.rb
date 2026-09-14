# frozen_string_literal: true

# Mapeo de una cuenta con su "team" en el proveedor de IA + el desglose de su saldo.
#
# El saldo tiene DOS componentes que se suman para formar el tope (max_budget) en el proveedor:
#   - plan_budget_cents      → lo que otorga el plan. Se RESTABLECE a su valor cada mes.
#   - purchased_budget_cents → lo que la cuenta compra aparte. Se ACUMULA; no se restablece.
#
# Todo en centavos de USD (enteros) para no arrastrar errores de coma flotante. El tope real
# enviado al proveedor es (plan + purchased) / 100.0.
# == Schema Information
#
# Table name: jabvox_ai_provider_accounts
#
#  id                            :bigint           not null, primary key
#  cached_spend_jabvox           :decimal(15, 6)
#  last_error_jabvox             :string
#  last_reset_period_jabvox      :string
#  plan_budget_cents_jabvox      :integer          default(0), not null
#  purchased_budget_cents_jabvox :integer          default(0), not null
#  spend_updated_at_jabvox       :datetime
#  status_jabvox                 :string           default("active"), not null
#  synced_at_jabvox              :datetime
#  team_id_jabvox                :string
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  account_id                    :bigint           not null
#
# Indexes
#
#  index_jabvox_ai_provider_accounts_on_account_id      (account_id) UNIQUE
#  index_jabvox_ai_provider_accounts_on_team_id_jabvox  (team_id_jabvox)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxAiProviderAccount < ApplicationRecord
  belongs_to :account

  STATUSES = %w[active blocked].freeze

  validates :account_id, uniqueness: true
  validates :status_jabvox, inclusion: { in: STATUSES }
  validates :plan_budget_cents_jabvox, :purchased_budget_cents_jabvox,
            numericality: { greater_than_or_equal_to: 0, only_integer: true }

  # Tope total (centavos) = saldo del plan + saldo comprado acumulado.
  def total_budget_cents
    plan_budget_cents_jabvox.to_i + purchased_budget_cents_jabvox.to_i
  end

  # Tope en USD (lo que espera el proveedor como max_budget).
  def total_budget_usd
    (total_budget_cents / 100.0).round(4)
  end

  # Saldo restante estimado (tope - gasto cacheado). Puede ir unos segundos atrasado.
  def remaining_usd
    (total_budget_usd - (cached_spend_jabvox || 0).to_f).round(4)
  end

  # Periodo actual 'YYYY-MM' según la zona horaria de la app.
  def self.current_period
    Time.current.strftime('%Y-%m')
  end

  # ¿Ya se restableció el saldo del plan este mes?
  def reset_done_this_period?
    last_reset_period_jabvox == self.class.current_period
  end

  def blocked?
    status_jabvox == 'blocked'
  end

  # Vista segura para la UI (sin secretos; el team_id no es secreto pero se marca su presencia).
  def summary
    {
      account_id: account_id,
      team_id: team_id_jabvox,
      status: status_jabvox,
      plan_budget_usd: (plan_budget_cents_jabvox / 100.0).round(4),
      purchased_budget_usd: (purchased_budget_cents_jabvox / 100.0).round(4),
      total_budget_usd: total_budget_usd,
      cached_spend_usd: (cached_spend_jabvox || 0).to_f.round(4),
      remaining_usd: remaining_usd,
      last_reset_period: last_reset_period_jabvox,
      synced_at: synced_at_jabvox
    }
  end
end
