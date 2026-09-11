# frozen_string_literal: true

# La ÚNICA conexión/cliente autorizado del Provisioner (PROVISIONER_CLIENT). Solo puede haber
# una sesión activa a la vez (índice único parcial). Fija la IP en el primer handshake; una
# petición desde otra IP o con otro client_id se rechaza y se audita.
# == Schema Information
#
# Table name: jabvox_provisioner_sessions
#
class JabvoxProvisionerSession < ApplicationRecord
  belongs_to :provisioner_api_token, class_name: 'JabvoxProvisionerApiToken', inverse_of: :sessions

  STATUSES = %w[active closed].freeze

  validates :status_jabvox, inclusion: { in: STATUSES }
  validates :client_id_jabvox, :bound_ip_jabvox, presence: true

  scope :active, -> { where(status_jabvox: 'active') }

  # Garantiza la sesión única para (token, client_id, ip). Si ya hay una activa con OTRA
  # identidad/IP, devuelve nil (conexión no autorizada → el controlador responde 403).
  # Atómico: bloquea las activas para evitar carreras de doble-conexión.
  def self.ensure_single!(token:, client_id:, ip:, fingerprint: nil)
    transaction do
      current = active.lock('FOR UPDATE').first
      if current.nil?
        create!(provisioner_api_token: token, client_id_jabvox: client_id.to_s,
                bound_ip_jabvox: ip.to_s, fingerprint_jabvox: fingerprint.presence,
                status_jabvox: 'active', last_heartbeat_at_jabvox: Time.current)
      elsif current.client_id_jabvox == client_id.to_s && current.bound_ip_jabvox == ip.to_s
        current.update!(last_heartbeat_at_jabvox: Time.current,
                        fingerprint_jabvox: fingerprint.presence || current.fingerprint_jabvox)
        current
      end
      # Distinta identidad/IP → el bloque devuelve nil (conexión no autorizada).
    end
  end
end
