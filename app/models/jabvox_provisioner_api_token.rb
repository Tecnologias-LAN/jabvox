# frozen_string_literal: true

# Token ÚNICO de la API Provisioner (Hermes → Jabvox). Reglas de seguridad:
#   - Existe como MÁXIMO 1 token activo en toda la app (índice único parcial + transacción
#     con bloqueo → imposible crear un segundo, ni siquiera en carrera).
#   - El token se genera con un CSPRNG (alta entropía) + sufijo "-tlan" y se muestra UNA sola
#     vez al crearlo. En BD se guarda SOLO el hash SHA-256; el original jamás se persiste,
#     no aparece en logs, respuestas, errores ni auditoría.
#   - La allowlist de IP y el checklist de permisos (ver/editar/crear por recurso) viven aquí
#     y se consultan FRESCOS en cada request (sin caché). Revocar/editar surte efecto en la
#     siguiente petición.
# == Schema Information
#
# Table name: jabvox_provisioner_api_tokens
#
class JabvoxProvisionerApiToken < ApplicationRecord
  # Acciones permitidas por recurso. NUNCA "delete"/"destroy": borrar está prohibido por
  # arquitectura en toda la superficie Provisioner.
  ACTIONS = %w[view edit create].freeze

  # Recursos gestionables (todo el Super Admin, sin credenciales). Fuente única para la UI
  # del checklist y para la validación de permisos.
  RESOURCES = %w[
    accounts users account_modules plans payment_gateways transactions
    limits ip_whitelists saldo softphone analytics_data_sources leads hermes_tokens
    ai_provider
  ].freeze

  # Recursos que SOLO admiten lectura (nunca edit/create): datos sensibles/financieros.
  READ_ONLY_RESOURCES = %w[payment_gateways transactions saldo analytics_data_sources].freeze

  STATUSES = %w[active revoked].freeze
  TOKEN_SUFFIX = '-tlan'
  TOKEN_ENTROPY_BYTES = 48 # 384 bits de aleatoriedad CSPRNG
  SIGNING_SECRET_BYTES = 48

  # El secreto de firma se guarda CIFRADO (no hasheado): hay que recuperarlo para verificar
  # la firma HMAC de cada request. Es independiente del token Bearer.
  encrypts :signing_secret_jabvox if Jabvox.encryption_configured?

  has_many :sessions, class_name: 'JabvoxProvisionerSession',
                      foreign_key: :provisioner_api_token_id, dependent: :destroy, inverse_of: :provisioner_api_token

  validates :status_jabvox, inclusion: { in: STATUSES }
  validates :token_hash_jabvox, presence: true, uniqueness: true
  validate :permissions_shape

  scope :active, -> { where(status_jabvox: 'active') }

  # Token activo actual (consulta FRESCA; sin caché de aplicación).
  def self.current_active
    active.order(:id).first
  end

  # Genera el token único. Devuelve [record, plaintext]. El plaintext se muestra UNA vez y se
  # descarta. Atómico: bloquea la tabla y revoca cualquier activo previo dentro de la misma
  # transacción, de modo que dos administradores simultáneos NO pueden crear dos activos (el
  # índice único parcial es la última línea de defensa, pero el bloqueo evita el error feo).
  def self.generate!(created_by_id:, allowed_ips: [], permissions: {}, label: nil)
    plaintext = "#{SecureRandom.urlsafe_base64(TOKEN_ENTROPY_BYTES)}#{TOKEN_SUFFIX}"
    signing_secret = SecureRandom.urlsafe_base64(SIGNING_SECRET_BYTES)
    hash = hash_token(plaintext)
    record = nil

    transaction do
      # Bloqueo pesimista sobre los activos para serializar generaciones concurrentes.
      active.lock('FOR UPDATE').each { |t| t.update!(status_jabvox: 'revoked', revoked_at_jabvox: Time.current) }
      # Cierra sesiones abiertas del token anterior (una sola conexión, siempre).
      JabvoxProvisionerSession.where(status_jabvox: 'active').update_all(status_jabvox: 'closed') # rubocop:disable Rails/SkipsModelValidations

      record = create!(
        token_hash_jabvox: hash,
        signing_secret_jabvox: signing_secret,
        token_prefix_jabvox: plaintext[0, 8],
        status_jabvox: 'active',
        allowed_ips_jabvox: Array(allowed_ips).map { |ip| ip.to_s.strip }.reject(&:blank?),
        permissions_jabvox: sanitize_permissions(permissions),
        label_jabvox: label.presence,
        created_by_id: created_by_id
      )
    end

    # El token Y el secreto de firma se muestran UNA sola vez. Hermes usa el token en el
    # header Bearer y el secreto (nunca transmitido después) como clave HMAC de la firma.
    [record, plaintext, signing_secret]
  end

  # Autentica un token en claro: hash + comparación en tiempo constante contra el activo.
  # Devuelve el registro o nil. NUNCA registra ni expone el token.
  def self.authenticate(plaintext)
    return nil if plaintext.blank?

    token = current_active
    return nil if token.nil?

    expected = token.token_hash_jabvox.to_s
    given = hash_token(plaintext)
    return nil unless ActiveSupport::SecurityUtils.secure_compare(given, expected)

    token
  end

  def self.hash_token(plaintext)
    Digest::SHA256.hexdigest(plaintext.to_s)
  end

  # Normaliza el checklist: solo recursos y acciones conocidos; nunca delete; los recursos
  # de solo lectura descartan edit/create aunque se pidan.
  def self.sanitize_permissions(raw)
    (raw || {}).each_with_object({}) do |(res, acts), acc|
      res = res.to_s
      next unless RESOURCES.include?(res)

      allowed = Array(acts).map(&:to_s) & ACTIONS
      allowed &= ['view'] if READ_ONLY_RESOURCES.include?(res)
      acc[res] = allowed.uniq if allowed.any?
    end
  end

  # ¿El token permite `action` sobre `resource`? Consulta FRESCA del jsonb en BD.
  # Nunca se puede conceder una acción sobre un recurso de solo lectura distinta de view.
  def allows?(resource, action)
    return false unless status_jabvox == 'active'
    return false unless RESOURCES.include?(resource.to_s) && ACTIONS.include?(action.to_s)
    return false if READ_ONLY_RESOURCES.include?(resource.to_s) && action.to_s != 'view'

    Array(permissions_jabvox[resource.to_s]).include?(action.to_s)
  end

  # ¿La IP origen está en la allowlist? Vacía = bloquea todo (nunca "permitir todas").
  def ip_allowed?(ip)
    ips = Array(allowed_ips_jabvox).map(&:to_s)
    ips.present? && ips.include?(ip.to_s)
  end

  def revoke!
    update!(status_jabvox: 'revoked', revoked_at_jabvox: Time.current)
    sessions.where(status_jabvox: 'active').update_all(status_jabvox: 'closed') # rubocop:disable Rails/SkipsModelValidations
  end

  def touch_used!
    update_column(:last_used_at_jabvox, Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  # Vista segura para la UI/auditoría: NUNCA el token ni su hash completo.
  def safe_summary
    {
      id: id, prefix: token_prefix_jabvox, status: status_jabvox,
      allowed_ips: Array(allowed_ips_jabvox), permissions: permissions_jabvox,
      label: label_jabvox, last_used_at: last_used_at_jabvox, created_at: created_at
    }
  end

  private

  def permissions_shape
    return if permissions_jabvox.is_a?(Hash)

    errors.add(:permissions_jabvox, 'debe ser un objeto de recurso→acciones')
  end
end
