# frozen_string_literal: true

# Config global (singleton) del proveedor de API de IA. Guarda la URL base y la master key
# (cifrada) del proxy. La master key es equivalente a root: NUNCA sale al frontend ni se
# expone en respuestas/logs; solo la usa el backend para las llamadas administrativas.
# == Schema Information
#
# Table name: jabvox_ai_provider_configs
#
class JabvoxAiProviderConfig < ApplicationRecord
  # No-determinístico + guard (patrón de los modelos jabvox_*): no se busca por la master key.
  encrypts :master_key_jabvox if Jabvox.encryption_configured?

  STATUSES = %w[disconnected connected error].freeze

  validates :provider_name_jabvox, presence: true
  validates :status_jabvox, inclusion: { in: STATUSES }

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
    update!(status_jabvox: 'error', last_check_at_jabvox: Time.current, last_error_jabvox: msg.to_s[0, 300])
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
