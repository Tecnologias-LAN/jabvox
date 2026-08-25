# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::AiChatService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  describe 'modo Hermes nativo (Sessions API, reenvía texto tal cual)' do
    let(:model) do
      create(:jabvox_ai_chat_model, account: account, source_jabvox: 'hermes',
                                    model_jabvox: 'hermes', name_jabvox: 'Hermes cuenta')
    end
    let(:service) { described_class.new(account: account, user: user, model_record: model) }
    let(:client) { instance_double(Jabvox::Hermes::SessionsClient) }

    before do
      create(:jabvox_context_forge_handoff, :ready, account: account, hermes_url: 'http://10.147.100.1:9119')
      allow(Jabvox::Hermes::SessionsClient).to receive(:new).and_return(client)
    end

    def ok(text: nil, session_id: nil, success: true, status: 200, error: nil)
      Jabvox::Hermes::SessionsClient::Result.new(success: success, text: text, session_id: session_id,
                                                 status: status, error: error)
    end

    it 'crea sesión la primera vez, la guarda y devuelve la respuesta' do
      allow(client).to receive(:create_session).and_return(ok(session_id: 'sess_1'))
      allow(client).to receive(:chat).with('sess_1', 'hola').and_return(ok(text: 'respuesta hermes', session_id: 'sess_1'))

      out = service.send_message(content: 'hola', session_id: nil, mode: 'chat')
      expect(out).to eq('respuesta hermes')
      expect(JabvoxHermesSession.for(account_id: account.id, user_id: user.id).session_id_jabvox).to eq('sess_1')
    end

    it 'reutiliza la sesión existente en el segundo mensaje' do
      JabvoxHermesSession.for(account_id: account.id, user_id: user.id).remember!('sess_prev')
      expect(client).to receive(:chat).with('sess_prev', '/model gpt-5').and_return(ok(text: 'modelo cambiado', session_id: 'sess_prev'))

      out = service.send_message(content: '/model gpt-5', session_id: nil, mode: 'chat')
      expect(out).to eq('modelo cambiado')
    end

    it '/new resetea la sesión y crea una nueva' do
      JabvoxHermesSession.for(account_id: account.id, user_id: user.id).remember!('sess_old')
      allow(client).to receive(:create_session).and_return(ok(session_id: 'sess_new'))
      allow(client).to receive(:chat).with('sess_new', '/new').and_return(ok(text: 'nueva conversación', session_id: 'sess_new'))

      out = service.send_message(content: '/new', session_id: nil, mode: 'chat')
      expect(out).to eq('nueva conversación')
    end

    it 'reintenta con sesión nueva si Hermes ya no reconoce la sesión (404)' do
      JabvoxHermesSession.for(account_id: account.id, user_id: user.id).remember!('sess_stale')
      allow(client).to receive(:chat).with('sess_stale', 'hola').and_return(ok(success: false, status: 404, error: 'not found'))
      allow(client).to receive(:create_session).and_return(ok(session_id: 'sess_fresh'))
      allow(client).to receive(:chat).with('sess_fresh', 'hola').and_return(ok(text: 'ok tras reintento', session_id: 'sess_fresh'))

      out = service.send_message(content: 'hola', session_id: nil, mode: 'chat')
      expect(out).to eq('ok tras reintento')
    end
  end
end
