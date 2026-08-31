# frozen_string_literal: true

# Ejecución de un flujo. `waiting` conserva el puntero de reanudación para que
# otro proceso pueda continuar por donde se suspendió.
# == Schema Information
#
# Table name: jabvox_flow_runs
#
#  id              :bigint           not null, primary key
#  error           :text
#  finished_at     :datetime
#  resume_at       :datetime
#  started_at      :datetime
#  status          :integer          default("pending"), not null
#  trigger         :jsonb            not null
#  triggered_by    :bigint
#  wait_reason     :string
#  wait_state      :jsonb
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  flow_id         :bigint           not null
#  version_id      :bigint           not null
#  waiting_node_id :string
#
# Indexes
#
#  idx_jabvox_flow_runs_account_status  (account_id,status)
#  idx_jabvox_flow_runs_flow_created    (flow_id,created_at)
#  idx_jabvox_flow_runs_status_resume   (status,resume_at)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (flow_id => jabvox_flows.id)
#  fk_rails_...  (triggered_by => users.id) ON DELETE => nullify
#  fk_rails_...  (version_id => jabvox_flow_versions.id)
#
class JabvoxFlowRun < ApplicationRecord
  belongs_to :account
  belongs_to :flow, class_name: 'JabvoxFlow'
  belongs_to :version, class_name: 'JabvoxFlowVersion', inverse_of: :runs
  belongs_to :triggerer, class_name: 'User', foreign_key: :triggered_by, optional: true, inverse_of: false
  has_many :steps, class_name: 'JabvoxFlowRunStep', foreign_key: :flow_run_id, dependent: :destroy,
                   inverse_of: :flow_run

  enum :status, { pending: 0, running: 1, success: 2, failed: 3, waiting: 4 }

  # Runs suspendidos cuyo instante de despertar ya pasó.
  scope :due, -> { where(status: :waiting).where(resume_at: ..Time.current) }
end
