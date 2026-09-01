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
#  index_jabvox_hermes_connections_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxHermesConnection < ApplicationRecord
  STATUSES = %w[unknown ok error].freeze

  encrypts :token_jabvox if Jabvox.encryption_configured?

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

  scope :ok, -> { where(status_jabvox: 'ok') }

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

  # Vista segura para el frontend (nunca el token).
  def safe_summary
    {
      id: id, name: name_jabvox, hermes_agent: hermes_agent_name_jabvox,
      base_url: base_url_jabvox, host_port: host_port, status: status_jabvox,
      has_token: token_jabvox.present?, last_error: last_error_jabvox,
      last_check_at: last_check_at_jabvox
    }
  end

  private

  # Todas las conexiones de una cuenta deben apuntar al MISMO host:puerto (mismo Hermes).
  def same_host_as_account_connections
    other = account&.jabvox_hermes_connections&.where&.not(id: id)&.first
    return if other.nil? || other.host_port == host_port

    errors.add(:base_url_jabvox,
               I18n.t('jabvox.hermes.same_host_required',
                      default: 'debe usar el mismo host y puerto que los demás agentes de esta cuenta'))
  end
end
