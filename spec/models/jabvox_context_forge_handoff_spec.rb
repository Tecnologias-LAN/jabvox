# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JabvoxContextForgeHandoff do
  let(:account) { create(:account) }

  describe 'validations' do
    it 'es único por cuenta' do
      create(:jabvox_context_forge_handoff, account: account)
      dup = build(:jabvox_context_forge_handoff, account: account)
      expect(dup).not_to be_valid
    end

    it 'rechaza un status inválido' do
      handoff = build(:jabvox_context_forge_handoff, account: account, status: 'nope')
      expect(handoff).not_to be_valid
    end
  end

  describe '#operational?' do
    it 'true solo cuando está ready con token y virtual server' do
      handoff = create(:jabvox_context_forge_handoff, :ready, account: account)
      expect(handoff).to be_operational
    end

    it 'false si está pending' do
      handoff = create(:jabvox_context_forge_handoff, account: account)
      expect(handoff).not_to be_operational
    end
  end

  describe '#safe_summary' do
    it 'nunca expone el scoped_token' do
      handoff = create(:jabvox_context_forge_handoff, :ready, account: account)
      summary = handoff.safe_summary
      expect(summary).not_to have_key(:scoped_token)
      expect(summary[:has_token]).to be(true)
    end
  end

  describe 'transiciones de estado' do
    let(:handoff) { create(:jabvox_context_forge_handoff, account: account) }

    it 'mark_failed guarda el motivo y lo trunca al límite de la columna' do
      handoff.mark_failed!('x' * 600)
      expect(handoff.reload.status).to eq('failed')
      expect(handoff.last_error.length).to eq(255)
    end

    it 'mark_ready fija provisioned_at y limpia el error' do
      handoff.mark_failed!('previo')
      handoff.mark_ready!(virtual_server_id: 'vs-1', scoped_token: 't', contextforge_base_url: 'u')
      expect(handoff.reload.status).to eq('ready')
      expect(handoff.last_error).to be_nil
      expect(handoff.provisioned_at).to be_present
    end
  end
end
