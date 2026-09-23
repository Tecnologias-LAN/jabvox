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
#  origin_jabvox                 :string           default("jabvox"), not null
#  plan_budget_cents_jabvox      :integer          default(0), not null
#  purchased_budget_cents_jabvox :integer          default(0), not null
#  remote_blocked_jabvox         :boolean          default(FALSE), not null
#  remote_max_budget_jabvox      :decimal(15, 6)
#  remote_models_jabvox          :jsonb            not null
#  spend_updated_at_jabvox       :datetime
#  status_jabvox                 :string           default("active"), not null
#  synced_at_jabvox              :datetime
#  team_alias_jabvox             :string
#  team_id_jabvox                :string
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  account_id                    :bigint
#
# Indexes
#
#  idx_ai_provider_accounts_account  (account_id) UNIQUE WHERE (account_id IS NOT NULL)
#  idx_ai_provider_accounts_team     (team_id_jabvox) UNIQUE WHERE ((team_id_jabvox IS NOT NULL) AND ((team_id_jabvox)::text <> ''::text))
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxAiProviderAccount < ApplicationRecord
  # Opcional: un team importado de LiteLLM puede existir sin cuenta ("huérfano") hasta que
  # un admin lo ligue desde el Super Admin.
  belongs_to :account, optional: true

  STATUSES = %w[active blocked].freeze
  ORIGINS = %w[jabvox litellm].freeze

  # Unicidad solo entre filas CON cuenta: varios huérfanos (account_id NULL) pueden coexistir.
  validates :account_id, uniqueness: true, allow_nil: true
  validates :status_jabvox, inclusion: { in: STATUSES }
  validates :origin_jabvox, inclusion: { in: ORIGINS }
  # Un mismo team del proxy no puede quedar ligado a dos filas (respaldado por índice único).
  validates :team_id_jabvox, uniqueness: true, allow_blank: true
  validates :plan_budget_cents_jabvox, :purchased_budget_cents_jabvox,
            numericality: { greater_than_or_equal_to: 0, only_integer: true }

  scope :orphans, -> { where(account_id: nil) }
  scope :linked, -> { where.not(account_id: nil) }

  # Team existente en el proxy pero sin cuenta de Jabvox asignada.
  def orphan?
    account_id.nil?
  end

  def imported?
    origin_jabvox == 'litellm'
  end

  # ¿Está operativo? Tener team en el proveedor es lo que habilita crear keys y consumir,
  # con independencia del saldo. El dashboard de la cuenta usa esto para saber si está
  # aprovisionada (antes miraba un campo que el backend nunca llegaba a enviar).
  def connected?
    team_id_jabvox.present?
  end

  # Tope ILIMITADO: el proveedor no le puso max_budget (null) y Jabvox tampoco le asignó
  # saldo propio. Un team así puede consumir sin límite en el proveedor — mostrarlo como
  # "$0.00" significaría justo lo contrario (agotado), así que se distingue explícitamente.
  # En cuanto Jabvox le asigna saldo (plan o comprado), ese tope manda y deja de ser ilimitado.
  def unlimited_budget?
    connected? && total_budget_cents.zero? && remote_max_budget_jabvox.nil?
  end

  # ¿El tope que Jabvox cree tener difiere del que reporta el proxy? Señal de divergencia
  # que la UI muestra para que el admin la resuelva (re-sincronizando).
  def budget_diverged?
    return false if remote_max_budget_jabvox.nil? || team_id_jabvox.blank?

    (remote_max_budget_jabvox.to_f - total_budget_usd).abs > 0.0001
  end

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

  # Restante, o nil si el tope es ilimitado: no existe un "restante" de un tope infinito
  # (devolver el negativo del gasto haría ver un saldo agotado que no lo está).
  def remaining_or_nil
    unlimited_budget? ? nil : remaining_usd
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
      # Lo consume el dashboard de la cuenta para saber si está aprovisionada.
      connected: connected?,
      unlimited: unlimited_budget?,
      status: status_jabvox,
      plan_budget_usd: (plan_budget_cents_jabvox / 100.0).round(4),
      purchased_budget_usd: (purchased_budget_cents_jabvox / 100.0).round(4),
      total_budget_usd: total_budget_usd,
      cached_spend_usd: (cached_spend_jabvox || 0).to_f.round(4),
      # nil cuando el tope es ilimitado: no existe "restante" de un tope infinito.
      remaining_usd: remaining_or_nil,
      last_reset_period: last_reset_period_jabvox,
      synced_at: synced_at_jabvox
    }.merge(provider_mirror)
  end

  # Lo que reporta el proveedor sobre este team (para mostrar divergencias en la UI).
  def provider_mirror
    {
      team_alias: team_alias_jabvox,
      remote_max_budget: remote_max_budget_jabvox&.to_f,
      remote_blocked: remote_blocked_jabvox,
      origin: origin_jabvox,
      orphan: orphan?,
      budget_diverged: budget_diverged?
    }
  end
end
