# frozen_string_literal: true

# Catálogo de planes de Jabvox, editable desde Super Admin. Es la fuente de verdad de
# qué habilita cada plan: módulos Jabvox, features nativas de Chatwoot, límites por
# recurso, precio, moneda, duración (días) y número de WhatsApp asociado.
#
# El aprovisionamiento (Jabvox::Billing::ProvisioningService) lee de aquí para saber
# qué activar cuando un pago del plan es aprobado.
#
# == Schema
#   name, slug (único), price_cents, currency, duration_days,
#   modules (jsonb array), chatwoot_features (jsonb array), limits (jsonb hash),
#   whatsapp_number, status (draft/active/in_development), sort_order
# == Schema Information
#
# Table name: jabvox_plans
#
#  id                :bigint           not null, primary key
#  billing_period    :integer          default("monthly"), not null
#  chatwoot_features :jsonb            not null
#  currency          :string           default("COP"), not null
#  duration_days     :integer          default(30), not null
#  limits            :jsonb            not null
#  modules           :jsonb            not null
#  name              :string           not null
#  price_cents       :integer          default(0), not null
#  slug              :string           not null
#  sort_order        :integer          default(0), not null
#  status            :integer          default("draft"), not null
#  whatsapp_number   :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
# Indexes
#
#  index_jabvox_plans_on_slug    (slug) UNIQUE
#  index_jabvox_plans_on_status  (status)
#
class JabvoxPlan < ApplicationRecord
  enum status: { draft: 0, active: 1, in_development: 2 }
  # Periodo de cobro. monthly ≈ 30 días, yearly ≈ 365. La vigencia real la fija
  # duration_days (así se pueden hacer planes a medida sin tocar el enum).
  enum billing_period: { monthly: 0, yearly: 1 }

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :price_cents, :duration_days, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true

  before_validation :set_slug, on: :create
  before_validation :sync_duration_with_period

  scope :ordered, -> { order(:sort_order, :id) }
  scope :sellable, -> { where(status: :active) }

  # Recursos concretos que se pasan al aprovisionamiento, en el formato que espera
  # Jabvox::AccountProvisioningService.
  def provisioning_params(email:, name: nil, idempotency_key: nil, base_url: nil)
    {
      email: email,
      name: name,
      modules: Array(modules).map(&:to_s),
      features: Array(chatwoot_features).map(&:to_s),
      limits: (limits || {}).symbolize_keys,
      idempotency_key: idempotency_key,
      base_url: base_url
    }.compact
  end

  def price
    price_cents.to_i / 100.0
  end

  private

  def set_slug
    self.slug = name.to_s.parameterize if slug.blank?
  end

  # Si no se fijó una duración a medida, deriva los días del periodo (30/365).
  def sync_duration_with_period
    return if duration_days.present? && duration_days.positive?

    self.duration_days = yearly? ? 365 : 30
  end
end
