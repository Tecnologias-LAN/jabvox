require 'rails_helper'

RSpec.describe Jabvox::Tickets::MergeService do
  let(:account) { create(:account) }
  let(:source) { create(:jabvox_ticket, account: account) }
  let(:target) { create(:jabvox_ticket, account: account) }

  it 'mueve los comentarios del origen al destino' do
    create(:jabvox_ticket_comment, ticket: source)
    create(:jabvox_ticket_comment, ticket: source)

    described_class.new(source: source, target: target).call

    expect(target.reload.comments.count).to eq(2)
    expect(source.reload.comments.count).to eq(0)
  end

  it 'marca el origen como resuelto/duplicado y lo archiva' do
    described_class.new(source: source, target: target).call
    source.reload

    expect(source.status_jabvox).to eq('resolved')
    expect(source.resolution_type_jabvox).to eq('duplicate')
    expect(source.archived?).to be(true)
  end

  it 'deja rastro en la bitácora de ambos tickets' do
    described_class.new(source: source, target: target).call

    expect(source.activities.where(action_jabvox: 'merged_into')).to exist
    expect(target.activities.where(action_jabvox: 'merge_received')).to exist
  end

  it 'no permite fusionar un ticket consigo mismo' do
    expect { described_class.new(source: source, target: source).call }
      .to raise_error(ArgumentError)
  end
end
