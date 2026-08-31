# frozen_string_literal: true

# Traza de ejecución por nodo. `input` lleva sellada la iteración del bucle a la
# que pertenece el paso, para poder inspeccionar cada vuelta después.
# == Schema Information
#
# Table name: jabvox_flow_run_steps
#
#  id          :bigint           not null, primary key
#  error       :text
#  finished_at :datetime
#  input       :jsonb
#  node_type   :string           not null
#  output      :jsonb
#  started_at  :datetime
#  status      :integer          default("pending"), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  flow_run_id :bigint           not null
#  node_id     :string           not null
#
# Indexes
#
#  idx_jabvox_flow_run_steps_run  (flow_run_id,id)
#
# Foreign Keys
#
#  fk_rails_...  (flow_run_id => jabvox_flow_runs.id)
#
class JabvoxFlowRunStep < ApplicationRecord
  belongs_to :flow_run, class_name: 'JabvoxFlowRun'

  enum :status, { pending: 0, running: 1, success: 2, failed: 3, skipped: 4, waiting: 5 }

  # Contexto de iteración sellado, o nil si el paso no corrió dentro de un bucle.
  def loop_context
    Jabvox::Flows::Engine::StepIteration.read(input)
  end

  # `input` sin el sello: es lo que el usuario configuró y lo que la UI muestra.
  def configured_input
    Jabvox::Flows::Engine::StepIteration.without_loop(input)
  end
end
