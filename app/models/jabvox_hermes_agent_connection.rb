# frozen_string_literal: true

# Unión N:N entre un agente de Jabvox (JabvoxHermesAgent, ligado a un usuario) y las
# conexiones a agentes de Hermes (JabvoxHermesConnection). Un agente Jabvox puede tener uno
# o varios agentes Hermes seleccionables en el Chat IA.
#
# == Schema Information
#
# Table name: jabvox_hermes_agent_connections
#
#  id                   :bigint           not null, primary key
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  hermes_agent_id      :bigint           not null
#  hermes_connection_id :bigint           not null
#
# Indexes
#
#  idx_hermes_agent_conn_unique                                   (hermes_agent_id,hermes_connection_id) UNIQUE
#  index_jabvox_hermes_agent_connections_on_hermes_agent_id       (hermes_agent_id)
#  index_jabvox_hermes_agent_connections_on_hermes_connection_id  (hermes_connection_id)
#
# Foreign Keys
#
#  fk_rails_...  (hermes_agent_id => jabvox_hermes_agents.id)
#  fk_rails_...  (hermes_connection_id => jabvox_hermes_connections.id)
#
class JabvoxHermesAgentConnection < ApplicationRecord
  belongs_to :hermes_agent, class_name: 'JabvoxHermesAgent'
  belongs_to :hermes_connection, class_name: 'JabvoxHermesConnection'

  validates :hermes_agent_id, uniqueness: { scope: :hermes_connection_id }
  validate :same_account

  private

  # El agente Jabvox y la conexión Hermes deben ser de la misma cuenta (anti cross-account).
  def same_account
    return if hermes_agent&.account_id == hermes_connection&.account_id

    errors.add(:base, 'el agente y la conexión deben ser de la misma cuenta')
  end
end
