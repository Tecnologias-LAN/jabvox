require 'rails_helper'

RSpec.describe Integrations::Openai::KeyValidator do
  let(:api_key) { 'sk-test-valid-key-123456789' }
  let(:probe_url) { 'https://api.openai.com/v1/models' }

  it 'accepts keys that OpenAI recognizes' do
    stub_request(:get, probe_url).to_return(status: 200)
    expect(described_class.valid?(api_key)).to be true
  end

  it 'rejects keys that OpenAI does not recognize' do
    stub_request(:get, probe_url).to_return(status: 401)
    expect(described_class.valid?(api_key)).to be false
  end

  it 'rejects blank keys without making a network call' do
    expect(described_class.valid?(nil)).to be false
    expect(described_class.valid?('')).to be false
  end

  it 'treats transient failures as valid to avoid blocking saves' do
    stub_request(:get, probe_url).to_return(status: 500)
    expect(described_class.valid?(api_key)).to be true

    stub_request(:get, probe_url).to_timeout
    expect(described_class.valid?(api_key)).to be true
  end

  it 'routes the probe through the per-integration base_url (NOT Captain/global config)' do
    custom_url = 'https://mi-ia.jabvox.co/v1/models'
    stub_request(:get, custom_url).to_return(status: 200)

    described_class.valid?(api_key, 'https://mi-ia.jabvox.co')

    expect(WebMock).to have_requested(:get, custom_url)
    expect(WebMock).not_to have_requested(:get, probe_url)
  end

  it 'does NOT fall back to CAPTAIN_OPEN_AI_ENDPOINT when base_url is blank' do
    # La validación ya no depende de Captain: sin base_url usa OpenAI oficial directo.
    stub_request(:get, probe_url).to_return(status: 200)
    described_class.valid?(api_key)
    expect(WebMock).to have_requested(:get, probe_url)
  end

  context 'with an OpenAI-compatible provider (own base_url)' do
    let(:base_url) { 'https://mi-ia.jabvox.co' }
    let(:models_url) { 'https://mi-ia.jabvox.co/v1/models' }
    let(:chat_url) { 'https://mi-ia.jabvox.co/v1/chat/completions' }

    it 'accepts a key valid for chat even if /models returns 401' do
      stub_request(:get, models_url).to_return(status: 401)
      stub_request(:post, chat_url).to_return(status: 200)
      expect(described_class.valid?(api_key, base_url)).to be true
    end

    it 'rejects when both /models and /chat/completions return 401' do
      stub_request(:get, models_url).to_return(status: 401)
      stub_request(:post, chat_url).to_return(status: 401,
                                              body: { error: { message: 'Invalid key' } }.to_json)
      result = described_class.validate(api_key, base_url)
      expect(result.valid?).to be false
      expect(result.code).to eq(401)
      expect(result.message).to include('Invalid key')
    end
  end

  it 'exposes a detailed Result with code and message' do
    stub_request(:get, probe_url).to_return(status: 200)
    result = described_class.validate(api_key)
    expect(result.valid?).to be true
    expect(result.code).to eq(200)
  end
end
