# frozen_string_literal: true

# Historial append-only de movimientos de saldo de IA de una cuenta. NUNCA se edita ni se
# borra: cada recarga comprada, cada restablecimiento mensual del plan y cada ajuste deja una
# fila con la foto del saldo resultante. La `idempotency_key` evita aplicar dos veces el mismo
# movimiento (webhook de pago reintentado, reset mensual re-encolado).
# == Schema Information
#
# Table name: jabvox_ai_balance_movements
#
#  id                                  :bigint           not null, primary key
#  amount_cents_jabvox                 :integer          default(0), not null
#  idempotency_key_jabvox              :string
#  kind_jabvox                         :string           not null
#  metadata_jabvox                     :jsonb            not null
#  plan_budget_cents_after_jabvox      :integer
#  purchased_budget_cents_after_jabvox :integer
#  reference_jabvox                    :string
#  created_at                          :datetime         not null
#  account_id                          :bigint           not null
#  jabvox_plan_id                      :bigint
#
# Indexes
#
#  idx_ai_balance_movements_account                 (account_id,created_at)
#  idx_ai_balance_movements_idem                    (idempotency_key_jabvox) UNIQUE WHERE (idempotency_key_jabvox IS NOT NULL)
#  index_jabvox_ai_balance_movements_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxAiBalanceMovement < ApplicationRecord
  belongs_to :account

  KINDS = %w[plan_assign plan_reset purchase adjustment].freeze

  validates :kind_jabvox, inclusion: { in: KINDS }
  validates :amount_cents_jabvox, numericality: { only_integer: true }

  scope :recent, -> { order(created_at: :desc) }
  after_create_commit :notify_account_administrators

  def push_event_data
    { id: id, kind: kind_jabvox, amount_cents: amount_cents_jabvox, created_at: created_at }
  end

  # Registra un movimiento de forma idempotente. Si ya existe uno con la misma
  # idempotency_key, no crea otro (devuelve el existente). Nunca revienta el flujo por la
  # colisión de unicidad.
  # rubocop:disable Metrics/ParameterLists
  def self.record!(account:, kind:, amount_cents:, plan_after:, purchased_after:,
                   plan_id: nil, reference: nil, idempotency_key: nil, metadata: {})
    if idempotency_key.present?
      existing = find_by(idempotency_key_jabvox: idempotency_key)
      return existing if existing
    end

    create!(
      account: account, kind_jabvox: kind, amount_cents_jabvox: amount_cents,
      plan_budget_cents_after_jabvox: plan_after, purchased_budget_cents_after_jabvox: purchased_after,
      jabvox_plan_id: plan_id, reference_jabvox: reference,
      idempotency_key_jabvox: idempotency_key.presence, metadata_jabvox: metadata || {},
      created_at: Time.current
    )
  rescue ActiveRecord::RecordNotUnique
    find_by(idempotency_key_jabvox: idempotency_key)
  end

  private

  def notify_account_administrators
    account.account_users.includes(:user).where(role: :administrator).find_each do |account_user|
      Jabvox::ModuleNotificationService.create!(
        account: account,
        user: account_user.user,
        type: :jabvox_ai_balance_movement,
        actor: self,
        title: 'Movimiento en el saldo de IA',
        body: I18n.t("jabvox.ai_balance_movement.#{kind_jabvox}", default: 'El saldo de IA de la cuenta fue actualizado.'),
        path: "/app/accounts/#{account_id}/settings/jabvox/ai-budget"
      )
    end
  end
  # rubocop:enable Metrics/ParameterLists
end
