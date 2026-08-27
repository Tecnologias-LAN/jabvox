# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::Hermes::SessionsClient do
  subject(:client) { described_class.new(base_url: 'http://10.147.100.1:9119', token: 'k', model: 'agente-miguel') }

  # Stub de la conexión Faraday interna (aísla la red; probamos el mapeo request/response).
  let(:conn) { instance_double(Faraday::Connection) }

  before { allow(client).to receive(:raw_conn).and_return(conn) } # rubocop:disable RSpec/SubjectStub

  def resp(status, body)
    instance_double(Faraday::Response, success?: status.between?(200, 299), status: status, body: body)
  end

  describe '#chat (OpenAI-compatible /v1/chat/completions)' do
    it 'envía messages y extrae el texto del choice' do
      expect(conn).to receive(:post).with('v1/chat/completions')
        .and_return(resp(200, { 'choices' => [{ 'message' => { 'content' => 'hola humano' } }] }))
      r = client.chat(nil, 'hola')
      expect(r).to be_success
      expect(r.text).to eq('hola humano')
    end

    it 'acepta un array de mensajes (multi-turno)' do
      allow(conn).to receive(:post).and_return(resp(200, { 'choices' => [{ 'message' => { 'content' => 'ok' } }] }))
      r = client.chat(nil, [{ role: 'user', content: 'hi' }, { role: 'assistant', content: 'yo' }])
      expect(r).to be_success
    end

    it 'reporta error remoto' do
      allow(conn).to receive(:post).and_return(resp(500, { 'error' => { 'message' => 'boom' } }))
      r = client.chat(nil, 'hi')
      expect(r).not_to be_success
      expect(r.error).to match(/500/)
    end
  end

  describe '#create_session (no-op stateless)' do
    it 'devuelve success sin session_id (API OpenAI es stateless)' do
      r = client.create_session
      expect(r).to be_success
      expect(r.session_id).to be_nil
    end
  end

  describe '#health' do
    it 'ok si /v1/health responde 200' do
      allow(conn).to receive(:get).and_return(resp(200, {}))
      expect(client.health).to be_success
    end
  end
end
