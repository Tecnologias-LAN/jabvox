# frozen_string_literal: true

# Config global (singleton) del proveedor de API de IA. Guarda la URL base y la master key
# (cifrada) del proxy. La master key es equivalente a root: NUNCA sale al frontend ni se
# expone en respuestas/logs; solo la usa el backend para las llamadas administrativas.
# == Schema Information
#
# Table name: jabvox_ai_provider_configs
#
#  id                   :bigint           not null, primary key
#  base_url_jabvox      :string
#  enabled_jabvox       :boolean          default(FALSE), not null
#  last_check_at_jabvox :datetime
#  last_error_jabvox    :string
#  master_key_jabvox    :text
#  provider_name_jabvox :string           default("Proveedor IA"), not null
#  status_jabvox        :string           default("disconnected"), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#
class JabvoxAiProviderConfig < ApplicationRecord
  # No-determinístico + guard (patrón de los modelos jabvox_*): no se busca por la master key.
  encrypts :master_key_jabvox if Jabvox.encryption_configured?

  STATUSES = %w[disconnected connected error].freeze

  validates :provider_name_jabvox, presence: true
  validates :status_jabvox, inclusion: { in: STATUSES }
  validate :base_url_uses_https

  # Singleton: siempre el de menor id; se crea si no existe.
  def self.instance
    order(:id).first || create!(provider_name_jabvox: 'Proveedor IA')
  end

  # ¿Está listo para operar? (habilitado + URL + master key presentes).
  def configured?
    enabled_jabvox && base_url_jabvox.present? && master_key_jabvox.present?
  end

  def mark_connected!
    update!(status_jabvox: 'connected', last_check_at_jabvox: Time.current, last_error_jabvox: nil)
  end

  def mark_error!(msg)
    # Nunca persistir un Bearer/master key aunque venga reflejado en el error del proveedor.
    safe = msg.to_s.gsub(/Bearer\s+\S+/i, 'Bearer [REDACTED]')
    safe = safe.gsub(master_key_jabvox, '[REDACTED]') if master_key_jabvox.present?
    update!(status_jabvox: 'error', last_check_at_jabvox: Time.current, last_error_jabvox: safe[0, 300])
  end

  # Exige HTTPS en la URL base (la master key viaja como Bearer): sin TLS iría en claro.
  # Se permite http solo a loopback/hosts locales para desarrollo.
  def base_url_uses_https # rubocop:disable Metrics/CyclomaticComplexity
    return if base_url_jabvox.blank?

    uri = begin
      URI.parse(base_url_jabvox)
    rescue URI::InvalidURIError
      nil
    end
    return errors.add(:base_url_jabvox, 'URL inválida') if uri.nil? || uri.host.blank?
    return if uri.scheme == 'https'

    local = %w[localhost 127.0.0.1 ::1].include?(uri.host) || uri.host.end_with?('.local')
    errors.add(:base_url_jabvox, 'debe usar https:// (salvo hosts locales)') unless local
  end

  # Vista segura para la UI/Super Admin: NUNCA expone la master key.
  def safe_summary
    {
      provider_name: provider_name_jabvox,
      base_url: base_url_jabvox,
      enabled: enabled_jabvox,
      master_key_set: master_key_jabvox.present?,
      status: status_jabvox,
      last_check_at: last_check_at_jabvox,
      last_error: last_error_jabvox
    }
  end
end
