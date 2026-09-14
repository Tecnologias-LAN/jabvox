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
#  id                     :bigint           not null, primary key
#  ai_budget_cents_jabvox :integer          default(0), not null
#  billing_period         :integer          default("monthly"), not null
#  chatwoot_features      :jsonb            not null
#  currency               :string           default("COP"), not null
#  duration_days          :integer          default(30), not null
#  limits                 :jsonb            not null
#  modules                :jsonb            not null
#  name                   :string           not null
#  price_cents            :integer          default(0), not null
#  slug                   :string           not null
#  sort_order             :integer          default(0), not null
#  status                 :integer          default("draft"), not null
#  whatsapp_number        :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#
# Indexes
#
#  index_jabvox_plans_on_slug    (slug) UNIQUE
#  index_jabvox_plans_on_status  (status)
#
class JabvoxPlan < ApplicationRecord
  BILLABLE_RESOURCE_KEYS = %w[
    agents
    inboxes
    forms
    advanced_flows
    automation_rules
    analytics_dashboards
    ai_documents
    email_templates
    storage_gb
  ].freeze

  enum status: { draft: 0, active: 1, in_development: 2 }
  # Periodo de cobro. monthly ≈ 30 días, yearly ≈ 365. La vigencia real la fija
  # duration_days (así se pueden hacer planes a medida sin tocar el enum).
  enum billing_period: { monthly: 0, yearly: 1 }

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :price_cents, :duration_days, numericality: { greater_than_or_equal_to: 0 }
  validates :ai_budget_cents_jabvox, numericality: { greater_than_or_equal_to: 0, only_integer: true }
  validates :currency, presence: true

  # Saldo mensual de IA del plan en USD (el que se restablece cada mes).
  def ai_budget_usd
    (ai_budget_cents_jabvox.to_i / 100.0).round(4)
  end

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
      limits: provisioning_limits.symbolize_keys,
      idempotency_key: idempotency_key,
      base_url: base_url
    }.compact
  end

  def price
    price_cents.to_i / 100.0
  end

  # Precio en la unidad principal (pesos/dólares), para ingresar y mostrar en el panel
  # sin pensar en centavos. Getter y setter mantienen price_cents en sincronía.
  #   price_in_pesos = 50000  => price_cents = 5_000_000 => cobra $50.000 COP.
  def price_in_pesos
    price_cents.to_i / 100
  end

  def price_in_pesos=(value)
    self.price_cents = (value.to_f * 100).round
  end

  # Saldo de IA en USD para el formulario del Super Admin (se guarda en centavos).
  #   ai_budget_in_usd = 3 => ai_budget_cents_jabvox = 300 => saldo mensual de $3 USD.
  def ai_budget_in_usd
    ai_budget_cents_jabvox.to_i / 100.0
  end

  def ai_budget_in_usd=(value)
    self.ai_budget_cents_jabvox = (value.to_f * 100).round
  end

  def included_limit_for(resource)
    value_for(resource, suffix: nil)
  end

  def unit_price_cents_for(resource)
    value_for(resource, suffix: 'unit_price_cents').to_i
  end

  def provisioning_limits
    raw_limits = (limits || {}).to_h.stringify_keys
    entitlements = raw_limits.each_with_object({}) do |(key, value), memo|
      memo[key] = value if scalar_number?(value)
    end

    BILLABLE_RESOURCE_KEYS.each do |resource|
      included = included_limit_for(resource)
      next if included.nil?

      entitlements[resource] = included
      entitlements["#{resource}_included"] ||= included

      unit_price = unit_price_cents_for(resource)
      entitlements["#{resource}_unit_price_cents"] ||= unit_price if unit_price.positive?
    end

    entitlements
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

  def value_for(resource, suffix:)
    raw_limits = (limits || {}).to_h.stringify_keys
    resource = resource.to_s
    direct_key = [resource, suffix].compact.join('_')

    return raw_limits[direct_key].to_i if scalar_number?(raw_limits[direct_key])

    nested = raw_limits[resource]
    return nested.to_i if suffix.nil? && scalar_number?(nested)
    return if nested.blank?

    nested_hash = nested.respond_to?(:to_h) ? nested.to_h.stringify_keys : {}
    nested_key = suffix.presence || 'included'
    nested_value = nested_hash[nested_key]
    nested_value.to_i if scalar_number?(nested_value)
  end

  def scalar_number?(value)
    return true if value.is_a?(Numeric)
    return false if value.blank?

    value.to_s.match?(/\A\d+\z/)
  end
end
