# frozen_string_literal: true

# Configuración WebRTC del softphone por cuenta, editable desde Super Admin: URL del
# WebSocket seguro (WSS) del PBX, dominio SIP, codecs, modo DTMF, autorespuesta,
# transferencia y servidores STUN/TURN.
#
# El turn_secret se cifra en BD: nunca se envía al cliente; con él se generan credenciales
# TURN temporales (HMAC, estilo coturn REST) que sí van al navegador con TTL corto.
#
# == Schema
#   account_id (único), enabled, wss_url, sip_domain, codecs (jsonb), auto_answer,
#   dtmf_mode, transfer_enabled, default_context, stun_servers (jsonb), turn_url,
#   turn_secret (cifrado), credential_ttl
# == Schema Information
#
# Table name: jabvox_softphone_configs
#
#  id               :bigint           not null, primary key
#  auto_answer      :boolean          default(FALSE), not null
#  codecs           :jsonb            not null
#  credential_ttl   :integer          default(3600), not null
#  default_context  :string           default("from-webrtc"), not null
#  dtmf_mode        :string           default("rfc2833"), not null
#  enabled          :boolean          default(FALSE), not null
#  sip_domain       :string
#  stun_servers     :jsonb            not null
#  transfer_enabled :boolean          default(TRUE), not null
#  turn_secret      :text
#  turn_url         :string
#  wss_url          :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#
# Indexes
#
#  index_jabvox_softphone_configs_on_account_id  (account_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxSoftphoneConfig < ApplicationRecord
  DTMF_MODES = %w[rfc2833 info inband].freeze

  belongs_to :account

  encrypts :turn_secret if Jabvox.encryption_configured?

  validates :account_id, uniqueness: true
  validates :dtmf_mode, inclusion: { in: DTMF_MODES }
  validates :credential_ttl, numericality: { greater_than: 0 }
  validates :wss_url, format: { with: %r{\Awss://}i }, allow_blank: true

  # Lista normalizada de codecs (siempre array de strings en minúscula).
  def codec_list
    Array(codecs).map { |c| c.to_s.downcase }
  end

  # Dominio SIP efectivo: el explícito o el HOST del Asterisk de VoIP de la cuenta.
  def effective_sip_domain
    sip_domain.presence || account&.jabvox_voip_config&.host.presence
  end

  # WSS efectivo: el explícito o uno derivado del dominio (puerto WSS estándar 8089).
  def effective_wss_url
    return wss_url if wss_url.present?

    domain = effective_sip_domain
    domain.present? ? "wss://#{domain}:8089/ws" : nil
  end

  # ¿Está listo para operar? (activo y con servidor resoluble, propio o vía VoIP).
  def operational?
    enabled? && effective_wss_url.present? && effective_sip_domain.present?
  end
end
