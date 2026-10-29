# frozen_string_literal: true

require 'rails_helper'
require_relative '../spec_helper_nodes'

# logic.delay — una espera por ENCIMA del umbral SUSPENDE el run (libera el worker);
# por debajo se duerme en el sitio. El umbral se bajó a 1 s para no retener un slot
# de Sidekiq hasta 5 s por nodo.
RSpec.describe Jabvox::Flows::Nodes::Logic::DelayNode do
  include NodeSpecHelpers

  let(:account) { create(:account) }
  let(:ctx) { build_ctx(account) }

  it 'suspende el run cuando la espera supera 1 s (no bloquea el worker)' do
    result = run_node(described_class, ctx, { 'ms' => 2_000 })

    expect(result.wait).to be_present
    expect(result.output['mode']).to eq('suspended')
    expect(result.output).to have_key('resumeAt')
  end

  it 'duerme en el sitio una espera corta (<= 1 s)' do
    expect_any_instance_of(described_class).to receive(:sleep).with(0.5)

    result = run_node(described_class, ctx, { 'ms' => 500 })

    expect(result.output['mode']).to eq('sync')
    expect(result.output['waited']).to be(true)
  end

  it 'el umbral de suspensión es 1 s' do
    expect(described_class::SYNC_THRESHOLD_MS).to eq(1_000)
  end

  it 'falla con milisegundos inválidos' do
    expect(run_node(described_class, ctx, { 'ms' => 'abc' }).error).to match(/inválidos/)
  end
end
