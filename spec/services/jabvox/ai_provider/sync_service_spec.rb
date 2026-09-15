require 'rails_helper'

RSpec.describe Jabvox::AiProvider::SyncService do
  let(:mock) { Jabvox::AiProvider::MockAdapter.new }
  let(:client) { Jabvox::AiProvider::Client.new(adapter: mock) }
  let(:service) { described_class.new(client: client) }

  describe '#sync_all!' do
    it 'importa un team que no existe en Jabvox y lo deja huérfano si no se puede mapear' do
      mock.seed_team(team_id: 'team-xyz', team_alias: 'cliente-suelto', max_budget: 25.0, spend: 3.5)

      result = service.sync_all!

      expect(result).to be_success
      expect(result.imported).to eq(1)

      row = JabvoxAiProviderAccount.find_by(team_id_jabvox: 'team-xyz')
      expect(row).to be_orphan
      expect(row).to be_imported
      expect(row.team_alias_jabvox).to eq('cliente-suelto')
      expect(row.remote_max_budget_jabvox.to_f).to eq(25.0)
      expect(row.cached_spend_jabvox.to_f).to eq(3.5)
    end

    it 'liga automáticamente por metadata.crm_id' do
      account = create(:account)
      mock.seed_team(team_id: 'team-meta', metadata: { 'crm_id' => account.id.to_s })

      result = service.sync_all!

      expect(result.linked).to eq(1)
      expect(JabvoxAiProviderAccount.find_by(team_id_jabvox: 'team-meta').account_id).to eq(account.id)
    end

    it 'liga automáticamente por el alias canónico crm-<id>' do
      account = create(:account)
      mock.seed_team(team_id: 'team-alias', team_alias: "crm-#{account.id}")

      service.sync_all!

      expect(JabvoxAiProviderAccount.find_by(team_id_jabvox: 'team-alias').account_id).to eq(account.id)
    end

    it 'no liga a una cuenta inexistente: la deja huérfana' do
      mock.seed_team(team_id: 'team-ghost', team_alias: 'crm-999999')

      service.sync_all!

      expect(JabvoxAiProviderAccount.find_by(team_id_jabvox: 'team-ghost')).to be_orphan
    end

    it 'es idempotente: sincronizar dos veces no duplica filas' do
      mock.seed_team(team_id: 'team-dup', team_alias: 'x')

      service.sync_all!
      second = service.sync_all!

      expect(second.imported).to eq(0)
      expect(second.updated).to eq(1)
      expect(JabvoxAiProviderAccount.where(team_id_jabvox: 'team-dup').count).to eq(1)
    end

    it 'no pisa el desglose de saldo local con el max_budget remoto' do
      account = create(:account)
      JabvoxAiProviderAccount.create!(account_id: account.id, team_id_jabvox: 'team-keep',
                                      plan_budget_cents_jabvox: 500,
                                      purchased_budget_cents_jabvox: 300)
      mock.seed_team(team_id: 'team-keep', max_budget: 99.0)

      service.sync_all!

      row = JabvoxAiProviderAccount.find_by(team_id_jabvox: 'team-keep')
      expect(row.plan_budget_cents_jabvox).to eq(500)
      expect(row.purchased_budget_cents_jabvox).to eq(300)
      # El valor remoto se guarda aparte y la divergencia queda visible.
      expect(row.remote_max_budget_jabvox.to_f).to eq(99.0)
      expect(row).to be_budget_diverged
    end

    it 'importa como huérfano si la cuenta inferida ya tiene otro team (no rompe el 1:1)' do
      account = create(:account)
      JabvoxAiProviderAccount.create!(account_id: account.id, team_id_jabvox: 'team-primero')
      mock.seed_team(team_id: 'team-segundo', metadata: { 'crm_id' => account.id.to_s })

      service.sync_all!

      expect(JabvoxAiProviderAccount.find_by(team_id_jabvox: 'team-segundo')).to be_orphan
      expect(JabvoxAiProviderAccount.where(account_id: account.id).count).to eq(1)
    end

    it 'refleja el bloqueo remoto en el estado local' do
      mock.seed_team(team_id: 'team-blocked')
      mock.request(:post, '/team/block', body: { 'team_id' => 'team-blocked' })

      service.sync_all!

      expect(JabvoxAiProviderAccount.find_by(team_id_jabvox: 'team-blocked').status_jabvox).to eq('blocked')
    end

    it 'devuelve el error del proveedor sin reventar' do
      failing = instance_double(Jabvox::AiProvider::Client)
      allow(failing).to receive(:list_teams)
        .and_return(Jabvox::AiProvider::Client::Result.new(success: false, error: 'boom'))

      result = described_class.new(client: failing).sync_all!

      expect(result).not_to be_success
      expect(result.error).to eq('boom')
    end
  end

  describe '#link_to_account! / #unlink!' do
    it 'liga un huérfano a una cuenta' do
      account = create(:account)
      orphan = JabvoxAiProviderAccount.create!(team_id_jabvox: 'team-o', origin_jabvox: 'litellm')

      service.link_to_account!(orphan, account)

      expect(orphan.reload.account_id).to eq(account.id)
    end

    it 'rechaza ligar si la cuenta ya tiene otro team' do
      account = create(:account)
      JabvoxAiProviderAccount.create!(account_id: account.id, team_id_jabvox: 'team-ya')
      orphan = JabvoxAiProviderAccount.create!(team_id_jabvox: 'team-nuevo')

      expect { service.link_to_account!(orphan, account) }
        .to raise_error(ArgumentError, /ya está ligada/)
      expect(orphan.reload).to be_orphan
    end

    it 'desliga dejando el team como huérfano' do
      account = create(:account)
      row = JabvoxAiProviderAccount.create!(account_id: account.id, team_id_jabvox: 'team-u')

      service.unlink!(row)

      expect(row.reload).to be_orphan
      expect(row.team_id_jabvox).to eq('team-u')
    end
  end

  describe 'normalización de /team/list' do
    it 'acepta tanto un array plano como un objeto envuelto' do
      flat = [{ 'team_id' => 'a' }]
      expect(Jabvox::AiProvider::Client.normalize_team_list(flat)).to eq(flat)
      expect(Jabvox::AiProvider::Client.normalize_team_list('teams' => flat)).to eq(flat)
      expect(Jabvox::AiProvider::Client.normalize_team_list('data' => flat)).to eq(flat)
      expect(Jabvox::AiProvider::Client.normalize_team_list(nil)).to eq([])
    end
  end
end
