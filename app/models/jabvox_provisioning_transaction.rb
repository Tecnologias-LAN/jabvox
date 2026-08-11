# frozen_string_literal: true

# Una fila por intento de pago→aprovisionamiento. Registra TODO lo que pasa entre el
# pago y el aprovisionamiento, con su estado, motivo y clave de idempotencia. Es lo que
# alimenta la visual de estados en el Super Admin.
#
# Estados (status):
#   payment_pending          - checkout creado, esperando confirmación de la pasarela
#   payment_rejected_invalid - la pasarela reportó pago inválido/no aprobado
#   payment_rejected_other   - rechazado por otro motivo (ver status_reason)
#   payment_approved         - pago verificado y aprobado (estado real consultado a la pasarela)
#   provisioning             - aprovisionando la cuenta
#   provisioned              - aprovisionado con éxito
#   provisioning_failed      - falló el aprovisionamiento tras los reintentos (ver status_reason)
#
# La idempotencia se garantiza por idempotency_key (único). El payload guardado está
# SANEADO (sin secretos ni datos sensibles).
# == Schema Information
#
# Table name: jabvox_provisioning_transactions
#
#  id                  :bigint           not null, primary key
#  amount_cents        :integer
#  attempts            :integer          default(0), not null
#  buyer_email         :string
#  currency            :string           default("COP")
#  gateway             :string           not null
#  gateway_reference   :string
#  idempotency_key     :string           not null
#  payload             :jsonb            not null
#  payment_approved_at :datetime
#  provisioned_at      :datetime
#  status              :integer          default("payment_pending"), not null
#  status_reason       :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint
#  jabvox_plan_id      :bigint
#
# Indexes
#
#  index_jabvox_provisioning_transactions_on_account_id         (account_id)
#  index_jabvox_provisioning_transactions_on_gateway_reference  (gateway_reference)
#  index_jabvox_provisioning_transactions_on_idempotency_key    (idempotency_key) UNIQUE
#  index_jabvox_provisioning_transactions_on_jabvox_plan_id     (jabvox_plan_id)
#  index_jabvox_provisioning_transactions_on_status             (status)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (jabvox_plan_id => jabvox_plans.id)
#
class JabvoxProvisioningTransaction < ApplicationRecord
  MAX_PROVISION_ATTEMPTS = 5

  belongs_to :account, optional: true
  belongs_to :jabvox_plan, optional: true

  enum status: {
    payment_pending: 0,
    payment_rejected_invalid: 1,
    payment_rejected_other: 2,
    payment_approved: 3,
    provisioning: 4,
    provisioned: 5,
    provisioning_failed: 6
  }

  validates :gateway, presence: true
  validates :idempotency_key, presence: true, uniqueness: true

  scope :recent, -> { order(created_at: :desc) }
  scope :needs_manual_action, -> { where(status: :provisioning_failed) }

  # Marca el pago como aprobado (idempotente: no pisa un estado ya avanzado).
  def mark_payment_approved!(reference: nil, amount_cents: nil)
    return if already_provisioned?

    update!(status: :payment_approved, gateway_reference: reference || gateway_reference,
            amount_cents: amount_cents || self.amount_cents, payment_approved_at: Time.current)
  end

  def mark_provisioning!
    update!(status: :provisioning)
  end

  def mark_provisioned!(account)
    update!(status: :provisioned, account: account, provisioned_at: Time.current, status_reason: nil)
  end

  def mark_provisioning_failed!(reason)
    update!(status: :provisioning_failed, status_reason: reason.to_s.truncate(500))
  end

  def mark_payment_rejected!(reason:, invalid: false)
    update!(status: invalid ? :payment_rejected_invalid : :payment_rejected_other,
            status_reason: reason.to_s.truncate(500))
  end

  def already_provisioned?
    provisioned? || provisioning?
  end

  def retriable?
    payment_approved? || provisioning_failed?
  end
end
