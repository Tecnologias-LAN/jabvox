# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::AiChatService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  describe 'modo Hermes nativo (API OpenAI-compat, reenvía texto tal cual)' do
    let(:model) do
      create(:jabvox_ai_chat_model, account: account, source_jabvox: 'hermes',
                                    model_jabvox: 'agente-miguel', name_jabvox: 'Hermes cuenta')
    end
    let(:service) { described_class.new(account: account, user: user, model_record: model) }
    let(:client) { instance_double(Jabvox::Hermes::SessionsClient) }

    before do
      create(:jabvox_context_forge_handoff, :ready, account: account, hermes_url: 'http://10.147.100.1:9119')
      allow(Jabvox::Hermes::SessionsClient).to receive(:new).and_return(client)
    end

    def ok(text:, success: true, error: nil)
      Jabvox::Hermes::SessionsClient::Result.new(success: success, text: text, error: error)
    end

    it 'reenvía el mensaje al Hermes de la cuenta y devuelve la respuesta' do
      expect(client).to receive(:chat).with(nil, [{ role: 'user', content: 'hola' }])
        .and_return(ok(text: 'respuesta hermes'))
      out = service.send_message(content: 'hola', session_id: nil, mode: 'chat')
      expect(out).to eq('respuesta hermes')
    end

    it 'reenvía comandos como /model TAL CUAL (Hermes los interpreta)' do
      expect(client).to receive(:chat).with(nil, [{ role: 'user', content: '/model gpt-5' }])
        .and_return(ok(text: 'modelo cambiado'))
      out = service.send_message(content: '/model gpt-5', session_id: nil, mode: 'chat')
      expect(out).to eq('modelo cambiado')
    end

    it 'reenvía el historial (multi-turno) + el mensaje actual' do
      hist = [
        double(role_jabvox: 'user', content_jabvox: 'primer mensaje'),
        double(role_jabvox: 'assistant', content_jabvox: 'primera respuesta')
      ]
      expect(client).to receive(:chat).with(nil, [
                                              { role: 'user', content: 'primer mensaje' },
                                              { role: 'assistant', content: 'primera respuesta' },
                                              { role: 'user', content: 'segundo' }
                                            ]).and_return(ok(text: 'ok'))
      out = service.send_message(content: 'segundo', session_id: nil, mode: 'chat', history: hist)
      expect(out).to eq('ok')
    end

    it 'usa el modelo del registro (p.ej. agente-miguel)' do
      expect(Jabvox::Hermes::SessionsClient).to receive(:new)
        .with(hash_including(model: 'agente-miguel')).and_return(client)
      allow(client).to receive(:chat).and_return(ok(text: 'x'))
      service.send_message(content: 'hola', session_id: nil, mode: 'chat')
    end

    it 'propaga el error si Hermes falla' do
      allow(client).to receive(:chat).and_return(ok(text: nil, success: false, error: 'timeout'))
      expect { service.send_message(content: 'hola', session_id: nil, mode: 'chat') }
        .to raise_error(/timeout/)
    end
  end
end
