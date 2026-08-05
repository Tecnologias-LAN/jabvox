require 'rails_helper'

RSpec.describe Jabvox::Tickets::BulkActionService do
  let(:account) { create(:account) }
  let(:actor) { create(:user) }
  let!(:t1) { create(:jabvox_ticket, account: account) }
  let!(:t2) { create(:jabvox_ticket, account: account) }
  let(:allow_all) { ->(_ticket, _query) { true } }

  it 'archiva varios tickets de una' do
    result = described_class.new(
      account: account, actor: actor, policy: allow_all,
      action: 'archive', ids: [t1.id, t2.id]
    ).call

    expect(result[:processed]).to contain_exactly(t1.id, t2.id)
    expect(t1.reload.archived?).to be(true)
    expect(t2.reload.archived?).to be(true)
  end

  it 'cambia el estado de varios respetando la máquina de estados' do
    result = described_class.new(
      account: account, actor: actor, policy: allow_all,
      action: 'change_status', ids: [t1.id], value: 'in_progress'
    ).call

    expect(result[:processed]).to eq([t1.id])
    expect(t1.reload.status_jabvox).to eq('in_progress')
  end

  it 'reporta fallidos sin abortar el lote' do
    # 'closed' → transición válida desde new_ticket, pero pedimos un salto inválido
    t1.change_status!('closed')
    result = described_class.new(
      account: account, actor: actor, policy: allow_all,
      action: 'change_status', ids: [t1.id, t2.id], value: 'in_progress'
    ).call

    expect(result[:failed]).to include(t1.id)   # closed → in_progress inválido
    expect(result[:processed]).to include(t2.id) # new → in_progress ok
  end

  it 'rechaza acciones no soportadas' do
    result = described_class.new(
      account: account, actor: actor, policy: allow_all,
      action: 'nuke', ids: [t1.id]
    ).call
    expect(result[:error]).to be_present
  end

  it 'salta los tickets no autorizados por la policy' do
    deny_t1 = ->(ticket, _q) { raise Pundit::NotAuthorizedError if ticket.id == t1.id }
    result = described_class.new(
      account: account, actor: actor, policy: deny_t1,
      action: 'archive', ids: [t1.id, t2.id]
    ).call

    expect(result[:failed]).to include(t1.id)
    expect(result[:processed]).to include(t2.id)
  end
end
