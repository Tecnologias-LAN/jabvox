require 'rails_helper'

RSpec.describe Jabvox::WhatsappFlows::PublishService do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                               provider_config: { 'api_key' => 'tok', 'phone_number_id' => '111', 'business_account_id' => 'waba-1' })
  end
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:flow) { create(:jabvox_whatsapp_flow, account: account, inbox: inbox, waba_id: 'waba-1') }
  let(:base) { 'https://graph.facebook.com/v22.0' }

  def json_headers
    { 'Content-Type' => 'application/json' }
  end

  def stub_meta_happy_path(meta_flow_id: 'meta-flow-1', publish: false)
    stub_request(:post, "#{base}/waba-1/flows").to_return(status: 200, body: { id: meta_flow_id }.to_json, headers: json_headers)
    stub_request(:post, "#{base}/#{meta_flow_id}/assets").to_return(status: 200, body: { validation_errors: [] }.to_json, headers: json_headers)
    stub_request(:get, "#{base}/#{meta_flow_id}")
      .with(query: hash_including('fields' => Jabvox::WhatsappFlows::MetaClient::FETCH_FIELDS))
      .to_return(status: 200, body: { id: meta_flow_id, status: 'DRAFT', validation_errors: [] }.to_json, headers: json_headers)
    stub_request(:post, "#{base}/#{meta_flow_id}/publish").to_return(status: 200, body: '{}', headers: json_headers) if publish
  end

  it 'refuses to sync an invalid flow, without contacting Meta' do
    flow.update!(screens_json: [])
    result = described_class.new(flow).call
    expect(result[:success]).to be(false)
    expect(flow.reload.status).to eq('sync_failed').or eq('draft')
    expect(WebMock).not_to have_requested(:post, /.*/)
  end

  it 'creates the flow in Meta, uploads the compiled JSON, and leaves it ready (not published) by default' do
    stub_meta_happy_path
    result = described_class.new(flow, user: nil).call(publish: false)

    expect(result[:success]).to be(true)
    flow.reload
    expect(flow.meta_flow_id).to eq('meta-flow-1')
    expect(flow.meta_status).to eq('DRAFT')
    expect(flow.status).to eq('ready')
    expect(flow.published_at).to be_nil
    expect(flow.versions.count).to eq(1)
  end

  it 'publishes on Meta and marks the flow published locally when publish: true' do
    stub_meta_happy_path(publish: true)
    result = described_class.new(flow, user: nil).call(publish: true)

    expect(result[:success]).to be(true)
    flow.reload
    expect(flow.status).to eq('published')
    expect(flow.published_at).to be_present
  end

  it 'reuses an existing meta_flow_id instead of creating a second Flow in Meta' do
    flow.update!(meta_flow_id: 'existing-flow')
    stub_request(:post, "#{base}/existing-flow/assets").to_return(status: 200, body: { validation_errors: [] }.to_json, headers: json_headers)
    stub_request(:get, "#{base}/existing-flow")
      .with(query: hash_including('fields' => Jabvox::WhatsappFlows::MetaClient::FETCH_FIELDS))
      .to_return(status: 200, body: { id: 'existing-flow', status: 'DRAFT' }.to_json, headers: json_headers)

    described_class.new(flow).call
    expect(WebMock).not_to have_requested(:post, "#{base}/waba-1/flows")
  end

  it 'marks the flow sync_failed and surfaces the Meta error when the upload fails' do
    stub_request(:post, "#{base}/waba-1/flows").to_return(status: 200, body: { id: 'meta-flow-1' }.to_json, headers: json_headers)
    stub_request(:post, "#{base}/meta-flow-1/assets").to_return(status: 400, body: { error: { message: 'Bad JSON' } }.to_json, headers: json_headers)

    result = described_class.new(flow).call
    expect(result[:success]).to be(false)
    expect(flow.reload.status).to eq('sync_failed')
  end
end
