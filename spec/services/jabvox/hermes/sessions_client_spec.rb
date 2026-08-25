# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::Hermes::SessionsClient do
  subject(:client) { described_class.new(base_url: 'http://10.147.100.1:9119', token: 'k') }

  # Stub de la conexión Faraday interna (aísla la red; probamos el mapeo request/response).
  let(:conn) { instance_double(Faraday::Connection) }

  before { allow(client).to receive(:conn).and_return(conn) } # rubocop:disable RSpec/SubjectStub

  def resp(status, body)
    instance_double(Faraday::Response, success?: status.between?(200, 299), status: status, body: body)
  end

  describe '#create_session' do
    it 'crea una sesión y extrae el id' do
      allow(conn).to receive(:post).and_return(resp(200, { 'id' => 'sess_123' }))
      r = client.create_session
      expect(r).to be_success
      expect(r.session_id).to eq('sess_123')
    end

    it 'tolera session_id como campo alterno' do
      allow(conn).to receive(:post).and_return(resp(200, { 'session_id' => 'sess_9' }))
      expect(client.create_session.session_id).to eq('sess_9')
    end
  end

  describe '#chat' do
    it 'envía {input:} y extrae el texto de output (string)' do
      expect(conn).to receive(:post).and_return(resp(200, { 'output' => 'hola humano' }))
      r = client.chat('sess_1', '/model gpt')
      expect(r).to be_success
      expect(r.text).to eq('hola humano')
    end

    it 'extrae texto cuando output es array de items' do
      allow(conn).to receive(:post).and_return(resp(200, { 'output' => [{ 'text' => 'parte1' }, { 'text' => 'parte2' }] }))
      expect(client.chat('s', 'hi').text).to eq("parte1\nparte2")
    end

    it 'reporta error remoto' do
      allow(conn).to receive(:post).and_return(resp(500, { 'error' => 'boom' }))
      r = client.chat('s', 'hi')
      expect(r).not_to be_success
      expect(r.error).to match(/500/)
      expect(r.status).to eq(500)
    end
  end

  describe '#health' do
    it 'ok si algún health responde 200' do
      allow(conn).to receive(:get).and_return(resp(200, {}))
      expect(client.health).to be_success
    end
  end
end
