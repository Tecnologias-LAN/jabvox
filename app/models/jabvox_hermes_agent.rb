# Un AGENTE del Hermes de una cuenta, ligado 1:1 a un usuario de la app.
#
# Los permisos del agente SON los del usuario ligado (JabvoxHermesUserPermission): el agente
# puede hacer exclusivamente lo que ese usuario tiene permitido. Así "agente" y "usuario"
# comparten una única fuente de verdad de autorización — el Authorizer valida contra ella.
#
# Cada cuenta con su Hermes trae 1 agente por defecto; el admin de la cuenta crea más
# agentes, cada uno ligado a un usuario, con nombre/prompt propios pero permisos del usuario.
# == Schema Information
#
# Table name: jabvox_hermes_agents
#
#  id                   :bigint           not null, primary key
#  description_jabvox   :text
#  is_default_jabvox    :boolean          default(FALSE), not null
#  name_jabvox          :string           not null
#  status_jabvox        :string           default("active"), not null
#  system_prompt_jabvox :text
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#  user_id              :bigint           not null
#
# Indexes
#
#  idx_hermes_agents_account_user            (account_id,user_id) UNIQUE
#  index_jabvox_hermes_agents_on_account_id  (account_id)
#  index_jabvox_hermes_agents_on_user_id     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxHermesAgent < ApplicationRecord
  STATUSES = %w[active disabled].freeze

  belongs_to :account
  belongs_to :user
  # El modelo de IA de este agente (cada agente tiene el suyo). nullify al borrar el agente.
  has_many :ai_chat_models, class_name: 'JabvoxAiChatModel',
                            foreign_key: :hermes_agent_id, dependent: :nullify, inverse_of: :hermes_agent

  validates :name_jabvox, presence: true
  validates :status_jabvox, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: { scope: :account_id }

  scope :active, -> { where(status_jabvox: 'active') }

  # Permisos efectivos del agente = permisos del usuario ligado en la cuenta.
  def permissions
    JabvoxHermesUserPermission.granted_for(account_id, user_id)
  end

  def active?
    status_jabvox == 'active'
  end
end
