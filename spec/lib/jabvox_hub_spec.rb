require 'rails_helper'

describe JabvoxHub do
  describe '.base_url' do
    it 'uses the static hub url' do
      expect(described_class::DEFAULT_BASE_URL).to eq('https://hub.2.jabvox.com')
      expect(described_class.base_url).to eq('https://hub.2.jabvox.com')
    end
  end

  it 'generates installation identifier' do
    installation_identifier = described_class.installation_identifier
    expect(installation_identifier).not_to be_nil
    expect(described_class.installation_identifier).to eq installation_identifier
  end

  context 'when fetching sync_with_hub' do
    it 'does not send any telemetry to an external hub' do
      allow(RestClient).to receive(:post)
      expect(described_class.sync_with_hub).to be_nil
      expect(RestClient).not_to have_received(:post)
    end
  end

  context 'when register instance' do
    it 'does not register the instance with any external hub' do
      allow(RestClient).to receive(:post)
      expect(described_class.register_instance('test', 'test', 'test@test.com')).to be_nil
      expect(RestClient).not_to have_received(:post)
    end
  end

  context 'when sending events' do
    it 'does not emit any event to an external hub' do
      allow(RestClient).to receive(:post)
      expect(described_class.emit_event('sample_event', { 'sample_data' => 'sample_data' })).to be_nil
      expect(RestClient).not_to have_received(:post)
    end
  end
end
