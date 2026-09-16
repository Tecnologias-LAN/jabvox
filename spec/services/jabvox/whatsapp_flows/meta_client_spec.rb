require 'rails_helper'

RSpec.describe Jabvox::WhatsappFlows::MetaClient do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              provider_config: { 'api_key' => 'secret_token_123', 'phone_number_id' => '111', 'business_account_id' => 'waba-1' })
  end
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:flow) { create(:jabvox_whatsapp_flow, account: account, inbox: inbox, waba_id: 'waba-1') }
  let(:client) { described_class.new(flow) }

  let(:base) { 'https://graph.facebook.com/v22.0' }

  describe '#update_json' do
    let(:flow) do
      create(:jabvox_whatsapp_flow, account: account, inbox: inbox, waba_id: 'waba-1',
                                    meta_flow_id: 'meta-flow-1')
    end

    # Contrastado contra la API real: el multipart de HTTParty omite la línea en
    # blanco que exige el estándar y Meta responde "(#100) The parameter file is
    # required"; este cuerpo, construido a mano, sí lo acepta.
    it 'sube el Flow JSON como multipart con el archivo, el nombre y el tipo de asset' do
      captured = nil
      stub = stub_request(:post, "#{base}/meta-flow-1/assets").to_return do |req|
        captured = { ctype: req.headers['Content-Type'].to_s, body: req.body.to_s }
        { status: 200, body: { success: true }.to_json, headers: { 'Content-Type' => 'application/json' } }
      end

      result = client.update_json({ version: '7.3', screens: [] })

      expect(result[:success]).to be(true)
      expect(stub).to have_been_requested
      expect(captured[:ctype]).to start_with('multipart/form-data')
      # La línea en blanco tras cada cabecera es justo lo que faltaba.
      expect(captured[:body]).to include(%(name="asset_type"\r\n\r\nFLOW_JSON))
      expect(captured[:body]).to include(%(name="file"; filename="flow.json"))
      expect(captured[:body]).to include('"version":"7.3"')
    end

    it 'devuelve el error de Meta de forma legible' do
      stub_request(:post, "#{base}/meta-flow-1/assets")
        .to_return(status: 400,
                   body: { error: { message: '(#100) The parameter file is required.' } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      result = client.update_json({ version: '7.3', screens: [] })

      expect(result[:success]).to be(false)
      expect(result[:error]).to include('parameter file is required')
    end
  end

  describe '#create' do
    it 'POSTs to /{WABA_ID}/flows with name and categories, and returns the new meta_flow_id' do
      stub = stub_request(:post, "#{base}/waba-1/flows")
             .with(body: hash_including('name' => flow.name, 'categories' => [flow.category]))
             .to_return(status: 200, body: { id: 'meta-flow-999' }.to_json, headers: { 'Content-Type' => 'application/json' })

      result = client.create
      expect(result[:success]).to be(true)
      expect(result[:meta_flow_id]).to eq('meta-flow-999')
      expect(stub).to have_been_requested
    end

    it 'surfaces a readable error and never leaks the access token when Meta rejects the request' do
      stub_request(:post, "#{base}/waba-1/flows")
        .to_return(status: 400, body: { error: { message: 'Invalid parameter', error_user_msg: 'Nombre inválido' } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      result = client.create
      expect(result[:success]).to be(false)
      expect(result[:error]).to include('Nombre inválido')
      expect(result[:error]).not_to include('secret_token_123')
    end
  end

  describe '#publish' do
    it 'POSTs to /{FLOW_ID}/publish' do
      flow.update!(meta_flow_id: 'meta-flow-999')
      stub = stub_request(:post, "#{base}/meta-flow-999/publish").to_return(status: 200, body: '{"success":true}')

      result = client.publish
      expect(result[:success]).to be(true)
      expect(stub).to have_been_requested
    end

    it 'fails locally without calling Meta when there is no meta_flow_id yet' do
      result = client.publish
      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/todavía no fue creado/)
      expect(WebMock).not_to have_requested(:post, /publish/)
    end
  end

  describe '#deprecate' do
    it 'POSTs to /{FLOW_ID}/deprecate' do
      flow.update!(meta_flow_id: 'meta-flow-999')
      stub = stub_request(:post, "#{base}/meta-flow-999/deprecate").to_return(status: 200, body: '{}')

      result = client.deprecate
      expect(result[:success]).to be(true)
      expect(stub).to have_been_requested
    end
  end

  describe '#fetch_status' do
    it 'GETs the flow and returns its parsed data' do
      flow.update!(meta_flow_id: 'meta-flow-999')
      stub_request(:get, "#{base}/meta-flow-999")
        .with(query: hash_including('fields' => described_class::FETCH_FIELDS))
        .to_return(status: 200, body: { id: 'meta-flow-999', status: 'DRAFT', validation_errors: [] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      result = client.fetch_status
      expect(result[:success]).to be(true)
      expect(result[:data]['status']).to eq('DRAFT')
    end
  end

  describe '#delete' do
    it 'only allows deleting a flow that is DRAFT on Meta' do
      flow.update!(meta_flow_id: 'meta-flow-999', meta_status: 'PUBLISHED')
      result = client.delete
      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/DRAFT/)
      expect(WebMock).not_to have_requested(:delete, /.*/)
    end

    it 'DELETEs when the flow is DRAFT on Meta' do
      flow.update!(meta_flow_id: 'meta-flow-999', meta_status: 'DRAFT')
      stub = stub_request(:delete, "#{base}/meta-flow-999").to_return(status: 200, body: '{"success":true}')

      result = client.delete
      expect(result[:success]).to be(true)
      expect(stub).to have_been_requested
    end
  end

  describe 'a non-Cloud-API channel' do
    it 'fails locally without ever hitting the network' do
      channel.update!(provider: 'default')
      result = client.create
      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/Cloud/)
      expect(WebMock).not_to have_requested(:post, /.*/)
    end
  end
end
