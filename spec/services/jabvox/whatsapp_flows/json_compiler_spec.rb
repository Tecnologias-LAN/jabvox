require 'rails_helper'

RSpec.describe Jabvox::WhatsappFlows::JsonCompiler do
  let(:screens) do
    [
      {
        'id' => 'welcome', 'title' => 'Inicio', 'terminal' => false, 'order' => 0,
        'components' => [
          { 'id' => 'cmp_1', 'type' => 'TextHeading', 'props' => { 'text' => 'Encuesta' } },
          { 'id' => 'cmp_2', 'type' => 'Footer', 'props' => { 'label' => 'Comenzar', 'action' => { 'name' => 'navigate', 'next' => 'rating' } } }
        ]
      },
      {
        'id' => 'rating', 'title' => 'Calificación', 'terminal' => true, 'order' => 1,
        'components' => [
          { 'id' => 'cmp_3', 'type' => 'RadioButtonsGroup',
            'props' => { 'name' => 'calificacion', 'label' => '¿Cómo calificas?', 'data_source' => [{ 'id' => 'a', 'title' => 'A' }], 'required' => true } },
          { 'id' => 'cmp_4', 'type' => 'Footer', 'props' => { 'label' => 'Enviar', 'action' => { 'name' => 'complete' } } }
        ]
      }
    ]
  end

  subject(:compiled) { described_class.new(screens).call }

  it 'sets the Flow JSON version to 7.3' do
    expect(compiled[:version]).to eq('7.3')
  end

  it 'compiles every screen with a SingleColumnLayout and its children' do
    expect(compiled[:screens].size).to eq(2)
    first = compiled[:screens].first
    expect(first[:id]).to eq('welcome')
    expect(first[:title]).to eq('Inicio')
    expect(first[:terminal]).to be(false)
    expect(first[:layout][:type]).to eq('SingleColumnLayout')
    expect(first[:layout][:children].size).to eq(2)
    expect(first[:layout][:children].first[:type]).to eq('TextHeading')
  end

  it 'marks the terminal screen correctly' do
    last = compiled[:screens].last
    expect(last[:terminal]).to be(true)
  end

  it 'orders screens by their `order` field regardless of array order' do
    out_of_order = screens.reverse
    result = described_class.new(out_of_order).call
    expect(result[:screens].map { |s| s[:id] }).to eq(%w[welcome rating])
  end

  it 'translates snake_case props to the kebab-case keys Meta expects (data_source -> data-source)' do
    radio = compiled[:screens].last[:layout][:children].first
    expect(radio).to have_key(:'data-source')
    expect(radio[:'data-source']).to eq([{ 'id' => 'a', 'title' => 'A' }])
  end

  it 'compiles a Footer action to on-click-action, not a generic action key' do
    footer = compiled[:screens].first[:layout][:children].last
    expect(footer).not_to have_key(:action)
    expect(footer[:'on-click-action']).to eq({ 'name' => 'navigate', 'next' => 'rating' })
  end

  it 'compiles a RadioButtonsGroup on-select action to on-select-action, not a generic action key' do
    screens_with_select_action = [
      {
        'id' => 'welcome', 'title' => 'Inicio', 'terminal' => true, 'order' => 0,
        'components' => [
          { 'id' => 'cmp_1', 'type' => 'RadioButtonsGroup',
            'props' => { 'name' => 'x', 'label' => 'X', 'data_source' => [{ 'id' => 'a', 'title' => 'A' }],
                         'action' => { 'name' => 'data_exchange' } } }
        ]
      }
    ]
    result = described_class.new(screens_with_select_action).call
    radio = result[:screens].first[:layout][:children].first
    expect(radio).not_to have_key(:action)
    expect(radio[:'on-select-action']).to eq({ 'name' => 'data_exchange' })
  end

  it 'does not emit a routing_model or endpoint_uri (v1 supports only endpoint-less flows)' do
    expect(compiled).not_to have_key(:routing_model)
    expect(compiled).not_to have_key(:endpoint_uri)
    expect(compiled).not_to have_key(:data_channel_uri)
  end

  it 'also accepts a JabvoxWhatsappFlow record directly' do
    account = create(:account)
    channel = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
    inbox = create(:inbox, account: account, channel: channel)
    flow = create(:jabvox_whatsapp_flow, account: account, inbox: inbox, screens_json: screens)

    result = described_class.new(flow).call
    expect(result[:version]).to eq('7.3')
    expect(result[:screens].size).to eq(2)
  end
end
