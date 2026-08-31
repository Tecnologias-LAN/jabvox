# frozen_string_literal: true

# Versión INMUTABLE del grafo de un flujo. Un run se ata a la versión con la que
# corrió, así editar el flujo no reescribe la historia de lo ya ejecutado.
# == Schema Information
#
# Table name: jabvox_flow_versions
#
#  id         :bigint           not null, primary key
#  created_by :bigint
#  graph      :jsonb            not null
#  version    :integer          not null
#  created_at :datetime         not null
#  flow_id    :bigint           not null
#
# Indexes
#
#  idx_jabvox_flow_versions_flow_version  (flow_id,version) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (created_by => users.id) ON DELETE => nullify
#  fk_rails_...  (flow_id => jabvox_flows.id)
#
class JabvoxFlowVersion < ApplicationRecord
  belongs_to :flow, class_name: 'JabvoxFlow'
  belongs_to :creator, class_name: 'User', foreign_key: :created_by, optional: true, inverse_of: false
  has_many :runs, class_name: 'JabvoxFlowRun', foreign_key: :version_id, dependent: :destroy,
                  inverse_of: :version

  validates :version, presence: true, uniqueness: { scope: :flow_id }

  # Grafo ya normalizado para el motor (tipo lógico + params).
  def engine_graph
    Jabvox::Flows::Engine::Graph.normalize(graph)
  end
end
