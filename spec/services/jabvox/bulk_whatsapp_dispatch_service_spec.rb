# frozen_string_literal: true

require 'rails_helper'

# Unit spec for the variable resolution that turns a variable_map + lead fields
# into processed_params (the { "1" => value } the template send forwards to Meta).
RSpec.describe Jabvox::BulkWhatsappDispatchService do
  subject(:service) do
    described_class.new(account: account, inbox: inbox, sender_user: user, actor: user)
  end

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }

  describe '#resolve_params (via send)' do
    let(:fields) do
      { 'nombre' => 'Mel', 'campaign' => 'C12', 'custom:zona' => 'Norte', 'email' => '' }
    end

    def resolve(map)
      service.send(:resolve_params, service.send(:normalize_variable_map, map), fields)
    end

    it 'maps {{n}} to the chosen lead field value' do
      expect(resolve('1' => 'nombre', '2' => 'campaign')).to eq('1' => 'Mel', '2' => 'C12')
    end

    it 'resolves a custom field key' do
      expect(resolve('1' => 'custom:zona')).to eq('1' => 'Norte')
    end

    it 'supports a literal "text:" value' do
      expect(resolve('1' => 'text:Hola fijo')).to eq('1' => 'Hola fijo')
    end

    it 'yields empty string for a missing field (never nil)' do
      expect(resolve('1' => 'no_existe')).to eq('1' => '')
    end

    it 'returns {} when the map is blank' do
      expect(resolve({})).to eq({})
    end

    it 'normalizes keys to bare digit strings and drops blank values' do
      normalized = service.send(:normalize_variable_map, '{{1}}' => 'nombre', '2' => '', '3' => 'email')
      expect(normalized).to eq('1' => 'nombre', '3' => 'email')
    end
  end

  # El token del envío ya no expira por tiempo (se revoca al terminar el batch). El cleanup
  # de respaldo espera una ventana proporcional al volumen por si el callback final se pierde.
  describe '#backup_cleanup_for (via send)' do
    it 'usa el piso para envíos pequeños' do
      expect(service.send(:backup_cleanup_for, 100)).to eq(described_class::BACKUP_CLEANUP_MIN)
    end

    it 'escala con el número de mensajes por encima del piso' do
      wait = service.send(:backup_cleanup_for, 20_000)
      expect(wait).to be > described_class::BACKUP_CLEANUP_MIN
      expect(wait).to eq(described_class::BACKUP_CLEANUP_PER_MESSAGE * 20_000)
    end

    it 'no supera el techo de seguridad' do
      expect(service.send(:backup_cleanup_for, 10_000_000)).to eq(described_class::BACKUP_CLEANUP_MAX)
    end
  end

  describe '#mint_ephemeral_token (via send)' do
    it 'crea un token SIN expiración por tiempo' do
      token = service.send(:mint_ephemeral_token)
      expect(token.expires_at).to be_nil
      expect(token).not_to be_expired
    end
  end
end
