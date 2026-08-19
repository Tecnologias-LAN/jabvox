# frozen_string_literal: true

# Handoff de aprovisionamiento Hermes/ContextForge de UNA cuenta. Es la fuente de verdad
# del aislamiento por tenant: el Consumer del Chat IA de la cuenta N arranca SOLO con estos
# datos (virtual_server_id + scoped_token), y ese token tiene alcance únicamente al virtual
# server de la cuenta N. Nunca puede tocar MCPs de otra cuenta.
#
# El scoped_token se guarda CIFRADO en reposo (Active Record Encryption). Nunca se expone
# al frontend ni se registra en logs.
#
# == Schema Information
#
# Table name: jabvox_context_forge_handoffs
#
#  id                     :bigint           not null, primary key
#  contextforge_base_url  :string
#  hermes_instance_id     :string
#  last_error             :string
#  mcp_servers            :jsonb            not null
#  provisioned_at         :datetime
#  scoped_token           :text
#  status                 :string           default("pending"), not null
#  team_id                :string
#  virtual_server_id      :string
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#
class JabvoxContextForgeHandoff < ApplicationRecord
  belongs_to :account

  encrypts :scoped_token if Jabvox.encryption_configured?

  STATUSES = %w[pending provisioning ready failed].freeze

  validates :account_id, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  scope :ready, -> { where(status: 'ready') }

  # ¿La cuenta tiene un Consumer operativo? (token + virtual server listos)
  def operational?
    status == 'ready' && scoped_token.present? && virtual_server_id.present? &&
      contextforge_base_url.present?
  end

  def mark_provisioning!
    update!(status: 'provisioning', last_error: nil)
  end

  def mark_ready!(attrs = {})
    update!(attrs.merge(status: 'ready', last_error: nil, provisioned_at: Time.current))
  end

  def mark_failed!(error)
    update!(status: 'failed', last_error: error.to_s.first(255))
  end

  # Vista segura para el frontend/logs: nunca incluye el token.
  def safe_summary
    {
      account_id: account_id,
      status: status,
      contextforge_base_url: contextforge_base_url,
      virtual_server_id: virtual_server_id,
      hermes_instance_id: hermes_instance_id,
      mcp_servers: mcp_servers,
      provisioned_at: provisioned_at,
      has_token: scoped_token.present?,
      last_error: last_error
    }
  end
end
