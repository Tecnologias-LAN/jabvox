# frozen_string_literal: true

# Auditoría de CADA petición a la API Provisioner. Nunca revienta el flujo principal.
# `sanitize` descarta cualquier clave sensible (token/secret/password/api_key/...) antes de
# persistir, de modo que ni el token ni credenciales aparezcan jamás en la auditoría.
# == Schema Information
#
# Table name: jabvox_provisioner_audit_logs
#
#  id                       :bigint           not null, primary key
#  action_jabvox            :string
#  http_status_jabvox       :integer
#  ip_jabvox                :string
#  outcome_jabvox           :string           not null
#  params_jabvox            :jsonb            not null
#  reason_jabvox            :string
#  resource_jabvox          :string
#  created_at               :datetime         not null
#  account_context_id       :integer
#  provisioner_api_token_id :bigint
#
# Indexes
#
#  idx_provisioner_audit_created   (created_at)
#  idx_provisioner_audit_resource  (resource_jabvox,action_jabvox)
#
class JabvoxProvisionerAuditLog < ApplicationRecord
  SENSITIVE = /token|secret|password|api[_-]?key|authorization|credential|sip_secret|turn_secret/i

  # Registra una entrada de auditoría. `entry` es un hash con claves simbólicas.
  def self.record!(entry)
    create!(
      provisioner_api_token_id: entry[:token_id],
      resource_jabvox: entry[:resource].to_s.presence,
      action_jabvox: entry[:action].to_s.presence,
      outcome_jabvox: entry[:outcome].to_s.presence || 'error',
      reason_jabvox: entry[:reason].to_s.presence,
      ip_jabvox: entry[:ip].to_s.presence,
      account_context_id: entry[:account_id],
      params_jabvox: sanitize(entry[:params]),
      http_status_jabvox: entry[:status],
      created_at: Time.current
    )
  rescue StandardError => e
    Rails.logger.error("[ProvisionerAudit] no se pudo auditar: #{e.class}")
    nil
  end

  # Elimina recursivamente claves sensibles y trunca valores largos.
  def self.sanitize(obj) # rubocop:disable Metrics/CyclomaticComplexity
    case obj
    when Hash, ActionController::Parameters
      obj.to_h.each_with_object({}) do |(k, v), acc|
        acc[k.to_s] = SENSITIVE.match?(k.to_s) ? '[REDACTED]' : sanitize(v)
      end
    when Array
      obj.first(50).map { |v| sanitize(v) }
    when String
      obj.length > 500 ? "#{obj[0, 500]}…" : obj
    else
      obj
    end
  end
end
