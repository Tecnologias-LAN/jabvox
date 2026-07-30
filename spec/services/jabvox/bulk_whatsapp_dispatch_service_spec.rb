# frozen_string_literal: true

require 'rails_helper'

# Unit spec for the variable resolution that turns a variable_map + lead fields
# into processed_params (the { "1" => value } the template send forwards to Meta).
RSpec.describe Jabvox::BulkWhatsappDispatchService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }

  subject(:service) do
    described_class.new(account: account, inbox: inbox, sender_user: user, actor: user)
  end

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
end
