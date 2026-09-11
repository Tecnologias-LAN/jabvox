# frozen_string_literal: true

# Historial append-only de movimientos de saldo de IA de una cuenta. NUNCA se edita ni se
# borra: cada recarga comprada, cada restablecimiento mensual del plan y cada ajuste deja una
# fila con la foto del saldo resultante. La `idempotency_key` evita aplicar dos veces el mismo
# movimiento (webhook de pago reintentado, reset mensual re-encolado).
# == Schema Information
#
# Table name: jabvox_ai_balance_movements
#
class JabvoxAiBalanceMovement < ApplicationRecord
  belongs_to :account

  KINDS = %w[plan_assign plan_reset purchase adjustment].freeze

  validates :kind_jabvox, inclusion: { in: KINDS }
  validates :amount_cents_jabvox, numericality: { only_integer: true }

  scope :recent, -> { order(created_at: :desc) }

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
  # rubocop:enable Metrics/ParameterLists
end
