# frozen_string_literal: true

# Conexión a UN agente del Hermes de la cuenta (API Server OpenAI-compatible por prefijo:
# http://<host:puerto>/p/<agente>/v1 + token del agente).
#
# Varias conexiones por cuenta = varios agentes en el MISMO Hermes. Se valida que todas
# compartan host:puerto (no se permiten varios Hermes distintos). El token se cifra en reposo.
#
# == Schema Information
#
# Table name: jabvox_hermes_connections
#
#  id                       :bigint           not null, primary key
#  action_token_jabvox      :text
#  base_url_jabvox          :string           not null
#  hermes_agent_name_jabvox :string           not null
#  last_check_at_jabvox     :datetime
#  last_error_jabvox        :string
#  name_jabvox              :string           not null
#  status_jabvox            :string           default("unknown"), not null
#  token_jabvox             :text
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint           not null
#
# Indexes
#
#  idx_hermes_conn_account_agent                  (account_id,hermes_agent_name_jabvox) UNIQUE
#  idx_hermes_conn_action_token                   (action_token_jabvox) UNIQUE WHERE (action_token_jabvox IS NOT NULL)
#  index_jabvox_hermes_connections_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxHermesConnection < ApplicationRecord
  STATUSES = %w[unknown ok error].freeze

  # token_jabvox: credencial App → Hermes (el Bearer que emite Hermes; lo pega el usuario).
  encrypts :token_jabvox if Jabvox.encryption_configured?
  # action_token_jabvox: credencial Hermes → Jabvox (única por conexión/Hermes). Deterministic
  # para poder resolver la conexión por su token en authenticate. Cada Hermes tiene el suyo.
  encrypts :action_token_jabvox, deterministic: true if Jabvox.encryption_configured?

  belongs_to :account

  has_many :agent_connections, class_name: 'JabvoxHermesAgentConnection',
                               foreign_key: :hermes_connection_id, dependent: :destroy,
                               inverse_of: :hermes_connection
  has_many :hermes_agents, through: :agent_connections

  validates :name_jabvox, presence: true
  validates :hermes_agent_name_jabvox, presence: true, uniqueness: { scope: :account_id }
  validates :base_url_jabvox, presence: true
  validates :status_jabvox, inclusion: { in: STATUSES }
  validate :same_host_as_account_connections
  validate :allowed_ips_are_parseable

  # Cada Hermes nace con su token de acción exclusivo (Hermes → Jabvox). Necesita el
  # account_id, así que se genera después de asignar la cuenta.
  before_validation :ensure_action_token, on: :create

  scope :ok, -> { where(status_jabvox: 'ok') }

  # Genera un token de acción opaco con el id de cuenta como SUFIJO: "<secreto>-<account_id>".
  # El secreto aleatorio garantiza unicidad; el sufijo permite verificar a qué cuenta
  # pertenece el token (doble candado anti cross-account en authenticate_action).
  def self.generate_action_token(account_id)
    "#{SecureRandom.urlsafe_base64(24)}-#{account_id}"
  end

  # Extrae el account_id del sufijo del token (o nil si no tiene el formato esperado).
  def self.account_id_from_token(token)
    m = token.to_s.match(/-(\d+)\z/)
    m && m[1].to_i
  end

  # Resuelve la conexión Hermes por su token de acción, para autenticar los requests entrantes
  # de ese Hermes. VALIDA que el sufijo -<account_id> del token coincida con la cuenta de la
  # conexión: un token solo entra a la cuenta que le corresponde (aislamiento estricto).
  def self.authenticate_action(token)
    return nil if token.blank?

    conn = find_by(action_token_jabvox: token.to_s)
    return nil if conn.nil?

    # El id embebido en el token debe coincidir con la cuenta real de la conexión.
    suffix_id = account_id_from_token(token)
    return nil if suffix_id.present? && suffix_id != conn.account_id

    conn
  end

  # ¿Este Hermes acepta ejecutar algo pedido desde `ip`?
  #
  # FAIL-CLOSED a propósito: sin IPs declaradas no se acepta NADA. El action_token por sí
  # solo no basta — si se filtra, sin esta allowlist serviría desde cualquier punto de
  # internet. Aquí exigimos además que el request venga del propio Hermes.
  #
  # Se aceptan rangos PRIVADOS (10.x, 172.16-31.x, 192.168.x): los Hermes desplegados sobre
  # ZeroTier llegan con IP de la red virtual. Esto es una allowlist de origen entrante, lo
  # contrario del guard SSRF (que restringe a dónde SALE Jabvox), así que aquí una IP
  # privada es legítima y esperada, no una señal de ataque.
  def ip_allowed?(ip)
    return false if ip.blank?

    ranges = parsed_allowed_ips
    return false if ranges.empty?

    candidate = IPAddr.new(ip.to_s)
    ranges.any? { |range| range.include?(candidate) }
  rescue IPAddr::InvalidAddressError
    false
  end

  # Entradas válidas (IP suelta o CIDR) ya parseadas; descarta en silencio las inválidas,
  # que la validación del modelo impide guardar de todos modos.
  def parsed_allowed_ips
    Array(allowed_ips_jabvox).filter_map do |entry|
      IPAddr.new(entry.to_s.strip)
    rescue IPAddr::InvalidAddressError
      nil
    end
  end

  # Rota el token de acción de este Hermes (revoca el anterior).
  def rotate_action_token!
    update!(action_token_jabvox: self.class.generate_action_token(account_id))
  end

  # Agente de la app (JabvoxHermesAgent) del que este Hermes hereda los PERMISOS al actuar
  # sobre la cuenta. Si hay varios ligados, se usa el primero de forma estable (por id).
  # Los permisos efectivos son EXACTAMENTE los del usuario de ese agente: si el usuario no
  # puede crear etiquetas, este token tampoco podrá.
  # Solo agentes ACTIVOS: desactivar un agente debe cortarle el paso también por esta vía,
  # igual que ya hace JabvoxHermesAgent.authenticate con el token de agente. Sin el filtro,
  # el token de conexión seguía ejecutando con un agente dado de baja.
  def action_agent
    hermes_agents.active.order(:id).first
  end

  def action_user
    action_agent&.user
  end

  # host:puerto (sin el prefijo /p/<agente>/v1). Identifica el Hermes físico de la cuenta.
  def host_port
    uri = URI.parse(base_url_jabvox)
    port = uri.port && uri.port != uri.default_port ? ":#{uri.port}" : ''
    "#{uri.scheme}://#{uri.host}#{port}"
  rescue URI::InvalidURIError
    base_url_jabvox
  end

  def mark_status!(success:, error: nil)
    update!(status_jabvox: success ? 'ok' : 'error', last_error_jabvox: error&.to_s&.first(255),
            last_check_at_jabvox: Time.current)
  end

  # Vista segura para el frontend (nunca los tokens).
  def safe_summary
    {
      id: id, name: name_jabvox, hermes_agent: hermes_agent_name_jabvox,
      base_url: base_url_jabvox, host_port: host_port, status: status_jabvox,
      has_token: token_jabvox.present?, has_action_token: action_token_jabvox.present?,
      last_error: last_error_jabvox, last_check_at: last_check_at_jabvox,
      # Las IPs no son un secreto (son la allowlist de origen, no una credencial) y la UI
      # las necesita para editarlas. `allowed_ips_configured` avisa de la conexión que aún
      # no acepta nada por no tener origen declarado.
      allowed_ips: Array(allowed_ips_jabvox),
      allowed_ips_configured: Array(allowed_ips_jabvox).any?
    }
  end

  private

  def ensure_action_token
    self.action_token_jabvox ||= self.class.generate_action_token(account_id)
  end

  # Todas las conexiones de una cuenta deben apuntar al MISMO host:puerto (mismo Hermes).
  def same_host_as_account_connections
    other = account&.jabvox_hermes_connections&.where&.not(id: id)&.first
    return if other.nil? || other.host_port == host_port

    errors.add(:base_url_jabvox,
               I18n.t('jabvox.hermes.same_host_required',
                      default: 'debe usar el mismo host y puerto que los demás agentes de esta cuenta'))
  end

  # Falla al guardar una entrada mal escrita en vez de descartarla en silencio: una IP con
  # un typo dejaría fuera al Hermes real sin que nadie se entere hasta que algo deje de
  # funcionar.
  def allowed_ips_are_parseable
    Array(allowed_ips_jabvox).each do |entry|
      value = entry.to_s.strip
      next if value.blank?

      begin
        IPAddr.new(value)
      rescue IPAddr::InvalidAddressError
        errors.add(:allowed_ips_jabvox,
                   I18n.t('jabvox.hermes.invalid_ip',
                          value: value,
                          default: '«%<value>s» no es una IP ni un rango CIDR válido'))
      end
    end
  end
end
