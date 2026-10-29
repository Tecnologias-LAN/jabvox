# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::Flows::StaleRunReaperJob do
  let(:account) { create(:account) }
  let(:flow) { JabvoxFlow.create!(account: account, name: 'F', status: :active) }
  let(:version) do
    v = JabvoxFlowVersion.create!(flow: flow, version: 1, graph: { 'nodes' => [], 'edges' => [] })
    flow.update!(current_version: v)
    v
  end

  def run_with(status:, created_at:)
    JabvoxFlowRun.create!(account: account, flow: flow, version: version, status: status,
                          trigger: { 'type' => 'test' }).tap do |r|
      r.update_columns(created_at: created_at, started_at: created_at) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  it 'marca failed un run running antiguo (worker caído a mitad)' do
    run = run_with(status: :running, created_at: 1.hour.ago)
    described_class.new.perform
    expect(run.reload).to be_failed
    expect(run.error).to include('interrumpida')
    expect(run.finished_at).to be_present
  end

  it 'marca failed un run pending antiguo (RunJob perdido antes de arrancar)' do
    run = run_with(status: :pending, created_at: 1.hour.ago)
    described_class.new.perform
    expect(run.reload).to be_failed
  end

  it 'NO toca un run running reciente (podría estar vivo)' do
    run = run_with(status: :running, created_at: 1.minute.ago)
    described_class.new.perform
    expect(run.reload).to be_running
  end

  it 'NO toca runs ya terminados' do
    run = run_with(status: :success, created_at: 1.hour.ago)
    described_class.new.perform
    expect(run.reload).to be_success
  end

  it 'NO toca runs waiting (los recoge SweepDueRunsJob, no el reaper)' do
    run = run_with(status: :waiting, created_at: 1.hour.ago)
    described_class.new.perform
    expect(run.reload).to be_waiting
  end

  it 'NO mata un run reanudado: created_at antiguo pero started_at reciente' do
    # Un run que esperó 1 h en waiting y acaba de reanudarse (started_at ahora)
    # está ejecutando su tramo final legítimamente: el reaper no debe tocarlo.
    run = JabvoxFlowRun.create!(account: account, flow: flow, version: version,
                                status: :running, trigger: { 'type' => 'test' })
    run.update_columns(created_at: 1.hour.ago, started_at: 10.seconds.ago) # rubocop:disable Rails/SkipsModelValidations

    described_class.new.perform

    expect(run.reload).to be_running
  end

  it 'SÍ mata un run running cuyo tramo (started_at) ya es antiguo' do
    run = JabvoxFlowRun.create!(account: account, flow: flow, version: version,
                                status: :running, trigger: { 'type' => 'test' })
    run.update_columns(created_at: 2.hours.ago, started_at: 1.hour.ago) # rubocop:disable Rails/SkipsModelValidations

    described_class.new.perform

    expect(run.reload).to be_failed
  end
end
