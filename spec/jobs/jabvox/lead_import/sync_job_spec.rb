# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::LeadImport::SyncJob do
  let(:account) { create(:account, jabvox_lead_import_enabled_jabvox: true) }
  let(:source) do
    account.jabvox_lead_sources.create!(
      name_jabvox: 'Externa', host_jabvox: 'db.example', database_jabvox: 'x',
      engine_jabvox: 'mariadb', status_jabvox: 'ok'
    )
  end

  before do
    # No tocar la BD externa real: el service es un doble que no hace nada.
    allow(Jabvox::LeadImport::SyncService).to receive(:new).and_return(
      instance_double(Jabvox::LeadImport::SyncService, call: true)
    )
    allow(account).to receive(:feature_enabled?).with('jabvox_lead_import').and_return(true)
  end

  it 'marca el source en ok tras un sync exitoso' do
    described_class.new.perform(source.id)
    expect(source.reload.status_jabvox).to eq('ok')
  end

  it 'marca error (no deja colgado en syncing) si el service falla' do
    allow(Jabvox::LeadImport::SyncService).to receive(:new).and_raise(StandardError, 'boom')
    described_class.new.perform(source.id)
    expect(source.reload.status_jabvox).to eq('error')
    expect(source.last_sync_result_jabvox['error']).to include('boom')
  end

  it 'no revienta si el source no existe' do
    expect { described_class.new.perform(-1) }.not_to raise_error
  end

  describe 'lock anti-duplicado (un solo sync por source a la vez)' do
    it 'omite un segundo sync del mismo source mientras el lock está tomado' do
      # RedisLock devuelve NOT_ACQUIRED: otro sync ya tiene el lock del source.
      allow(Jabvox::RedisLock).to receive(:with_lock).and_return(Jabvox::RedisLock::NOT_ACQUIRED)
      expect(Jabvox::LeadImport::SyncService).not_to receive(:new)
      described_class.new.perform(source.id)
      # El estado no se toca: no arrancó ningún sync.
      expect(source.reload.status_jabvox).to eq('ok')
    end
  end

  describe 'aislamiento por cuenta' do
    it 'el lock usa una clave distinta por source (una cuenta no bloquea a otra)' do
      other = create(:account, jabvox_lead_import_enabled_jabvox: true)
      other_source = other.jabvox_lead_sources.create!(
        name_jabvox: 'Otra', host_jabvox: 'db2.example', database_jabvox: 'y', engine_jabvox: 'mariadb'
      )
      keys = []
      allow(Jabvox::RedisLock).to receive(:with_lock) do |key, **|
        keys << key
        nil
      end
      described_class.new.perform(source.id)
      described_class.new.perform(other_source.id)
      # Claves distintas por source: una cuenta no puede bloquear el sync de otra.
      expect(keys).to contain_exactly(
        "jabvox:lead_import:sync:#{source.id}",
        "jabvox:lead_import:sync:#{other_source.id}"
      )
    end
  end
end
