require 'rails_helper'

# Flujo completo end-to-end contra el adaptador mock: Jabvox crea un team, el proveedor
# tiene además teams creados por fuera, y la sincronización deja todo reflejado.
#
# Es un test de flujo, no de una clase: cubre la interacción entre BalanceService, SyncService
# y el adaptador, en secuencia. Partirlo en ejemplos de una aserción rompería precisamente lo
# que se quiere verificar (que cada paso deja el estado correcto para el siguiente).
# rubocop:disable RSpec/DescribeClass, RSpec/MultipleExpectations
RSpec.describe 'Sincronización LiteLLM ↔ Jabvox (flujo completo)' do
  let(:mock) { Jabvox::AiProvider::MockAdapter.new }
  let(:client) { Jabvox::AiProvider::Client.new(adapter: mock) }

  it 'refleja en Jabvox tanto sus propios teams como los creados por fuera' do
    # (1) Una cuenta se da de alta desde Jabvox: crea su team en el proveedor.
    propia = create(:account)
    Jabvox::AiProvider::BalanceService.new(propia, client: client).manual_setup!(initial_cents: 1_000)

    row = JabvoxAiProviderAccount.find_by(account_id: propia.id)
    expect(row.team_id_jabvox).to be_present
    expect(row.total_budget_usd).to eq(10.0)

    # (2) Alguien creó dos teams directamente en LiteLLM, sin pasar por Jabvox:
    #     uno mapeable a una cuenta existente y otro que no.
    mapeable = create(:account)
    mock.seed_team(team_id: 'team-externo-1', team_alias: "crm-#{mapeable.id}", max_budget: 30.0, spend: 2.0)
    mock.seed_team(team_id: 'team-externo-2', team_alias: 'proyecto-ajeno', max_budget: 5.0)

    # (3) Sincronizar: trae TODO.
    expect(Jabvox::AiProvider::SyncService.new(client: client).sync_all!).to be_success

    # El team propio se actualizó, no se duplicó.
    expect(JabvoxAiProviderAccount.where(account_id: propia.id).count).to eq(1)

    # El externo mapeable quedó ligado a su cuenta, con el espejo del proveedor.
    externo1 = JabvoxAiProviderAccount.find_by(team_id_jabvox: 'team-externo-1')
    expect(externo1.account_id).to eq(mapeable.id)
    expect(externo1.remote_max_budget_jabvox.to_f).to eq(30.0)
    expect(externo1.cached_spend_jabvox.to_f).to eq(2.0)

    # El no mapeable quedó huérfano, a la espera de que un admin lo ligue.
    externo2 = JabvoxAiProviderAccount.find_by(team_id_jabvox: 'team-externo-2')
    expect(externo2).to be_orphan

    # (4) El admin liga el huérfano a una cuenta desde la UI.
    destino = create(:account)
    Jabvox::AiProvider::SyncService.new(client: client).link_to_account!(externo2, destino)
    expect(externo2.reload.account_id).to eq(destino.id)

    # (5) Re-sincronizar es seguro: no duplica ni deshace el vínculo manual.
    Jabvox::AiProvider::SyncService.new(client: client).sync_all!
    expect(externo2.reload.account_id).to eq(destino.id)
    expect(JabvoxAiProviderAccount.where(team_id_jabvox: 'team-externo-2').count).to eq(1)
  end

  it 'no envía los módulos del plan como si fueran modelos LLM' do
    plan = JabvoxPlan.create!(name: 'Plan con módulos', ai_budget_cents_jabvox: 500, modules: %w[dialer cdr])
    account = create(:account, jabvox_plan_id: plan.id)

    Jabvox::AiProvider::BalanceService.new(account, client: client).apply_plan!(plan)

    team_id = JabvoxAiProviderAccount.find_by(account_id: account.id).team_id_jabvox
    info = client.team_info(team_id)
    # models vacío = sin restricción de catálogo. Nunca 'dialer'/'cdr'.
    expect(info.data.dig('team_info', 'models')).to eq([])
  end
end
# rubocop:enable RSpec/DescribeClass, RSpec/MultipleExpectations
