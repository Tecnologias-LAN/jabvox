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

  # Los componentes de una pantalla van dentro de un Form: Meta solo resuelve
  # las referencias ${form.campo} dentro de él, y sin eso la respuesta del
  # formulario llega vacía (solo con el flow_token).
  def children_of(screen)
    form = screen[:layout][:children].first
    expect(form[:type]).to eq('Form')
    form[:children]
  end

  it 'compiles every screen with a SingleColumnLayout and its children inside a Form' do
    expect(compiled[:screens].size).to eq(2)
    first = compiled[:screens].first
    expect(first[:id]).to eq('welcome')
    expect(first[:title]).to eq('Inicio')
    expect(first[:terminal]).to be(false)
    expect(first[:layout][:type]).to eq('SingleColumnLayout')

    form = first[:layout][:children].first
    expect(first[:layout][:children].size).to eq(1)
    expect(form[:type]).to eq('Form')
    expect(form[:name]).to be_present
    expect(form[:children].size).to eq(2)
    expect(form[:children].first[:type]).to eq('TextHeading')
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
    radio = children_of(compiled[:screens].last).first
    expect(radio).to have_key(:'data-source')
    expect(radio[:'data-source']).to eq([{ 'id' => 'a', 'title' => 'A' }])
  end

  it 'compiles a Footer action to on-click-action, not a generic action key' do
    footer = children_of(compiled[:screens].first).last
    expect(footer).not_to have_key(:action)
    # Meta espera el destino como objeto, no como el id suelto: un `next` en
    # texto plano hace que rechace el Flow al publicarlo.
    action = footer[:'on-click-action']
    expect(action['name']).to eq('navigate')
    expect(action['next']).to eq({ 'type' => 'screen', 'name' => 'rating' })
  end

  # El payload es lo que hace que Meta devuelva las respuestas: sin él manda un
  # nfm_reply con el flow_token y nada más, que es el bug que se corrigió.
  it 'declares in the complete payload the fields of its own screen' do
    footer = children_of(compiled[:screens].last).last
    expect(footer[:'on-click-action']['name']).to eq('complete')
    expect(footer[:'on-click-action']['payload']).to eq({ 'calificacion' => '${form.calificacion}' })
  end

  it 'carries the answers of earlier screens through to the final complete' do
    two_screens = [
      { 'id' => 'uno', 'title' => 'Uno', 'order' => 0, 'components' => [
        { 'type' => 'CheckboxGroup', 'props' => { 'name' => 'servicios', 'label' => 'S',
                                                  'data_source' => [{ 'id' => 'a', 'title' => 'A' }] } },
        { 'type' => 'Footer', 'props' => { 'label' => 'Siguiente', 'action' => { 'name' => 'navigate', 'next' => 'dos' } } }
      ] },
      { 'id' => 'dos', 'title' => 'Dos', 'order' => 1, 'terminal' => true, 'components' => [
        { 'type' => 'TextInput', 'props' => { 'name' => 'comentario', 'label' => 'C' } },
        { 'type' => 'Footer', 'props' => { 'label' => 'Enviar', 'action' => { 'name' => 'complete' } } }
      ] }
    ]
    result = described_class.new(two_screens).call
    primera, ultima = result[:screens]

    # La primera pantalla reenvía lo suyo al navegar…
    navigate = primera[:layout][:children].first[:children].last[:'on-click-action']
    expect(navigate['payload']).to eq({ 'servicios' => '${form.servicios}' })

    # …la segunda lo declara en su `data` (array, por ser CheckboxGroup)…
    expect(ultima[:data]['servicios']).to include('type' => 'array')

    # …y el complete final devuelve lo propio y lo heredado.
    complete = ultima[:layout][:children].first[:children].last[:'on-click-action']
    expect(complete['payload']).to eq(
      { 'comentario' => '${form.comentario}', 'servicios' => '${data.servicios}' }
    )
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
    radio = children_of(result[:screens].first).first
    expect(radio).not_to have_key(:action)
    expect(radio[:'on-select-action']['name']).to eq('data_exchange')
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
