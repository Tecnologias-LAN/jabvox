require 'rails_helper'

RSpec.describe Jabvox::WhatsappFlows::Validator do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { create(:inbox, account: account, channel: channel) }

  def flow_with(screens)
    account.jabvox_whatsapp_flows.create!(inbox: inbox, waba_id: '123', name: 'Test', category: 'SURVEY', screens_json: screens)
  end

  def footer(label, action)
    { 'id' => 'footer', 'type' => 'Footer', 'props' => { 'label' => label, 'action' => action } }
  end

  # Caso 1: encuesta simple, una pregunta, dos pantallas.
  it 'accepts a simple two-screen survey (welcome + one question, terminal)' do
    screens = [
      { 'id' => 'welcome', 'title' => 'Inicio', 'terminal' => false, 'order' => 0,
        'components' => [
          { 'id' => 'h1', 'type' => 'TextHeading', 'props' => { 'text' => 'Hola' } },
          footer('Comenzar', { 'name' => 'navigate', 'next' => 'q1' })
        ] },
      { 'id' => 'q1', 'title' => 'Pregunta', 'terminal' => true, 'order' => 1,
        'components' => [
          { 'id' => 'r1', 'type' => 'RadioButtonsGroup',
            'props' => { 'name' => 'satisfaccion', 'label' => '¿Satisfecho?', 'data_source' => [{ 'id' => 'si', 'title' => 'Sí' }, { 'id' => 'no', 'title' => 'No' }] } },
          footer('Enviar', { 'name' => 'complete' })
        ] }
    ]
    result = described_class.new(flow_with(screens)).call
    expect(result[:valid]).to be(true)
    expect(result[:errors]).to eq([])
  end

  # Caso 2: múltiples preguntas por pantalla.
  it 'accepts multiple question components on a single screen' do
    screens = [
      { 'id' => 'form', 'title' => 'Formulario', 'terminal' => true, 'order' => 0,
        'components' => [
          { 'id' => 't1', 'type' => 'TextInput', 'props' => { 'name' => 'nombre', 'label' => 'Nombre' } },
          { 'id' => 't2', 'type' => 'TextInput', 'props' => { 'name' => 'correo', 'label' => 'Correo', 'input_type' => 'email' } },
          { 'id' => 'd1', 'type' => 'Dropdown', 'props' => { 'name' => 'ciudad', 'label' => 'Ciudad', 'data_source' => [{ 'id' => 'bog', 'title' => 'Bogotá' }] } },
          footer('Enviar', { 'name' => 'complete' })
        ] }
    ]
    result = described_class.new(flow_with(screens)).call
    expect(result[:valid]).to be(true)
  end

  # Caso 3: flow largo de 5+ pantallas — no debe haber límite artificial de pantallas.
  it 'accepts a flow with more than five screens with no artificial screen-count limit' do
    screens = (0..6).map do |i|
      terminal = i == 6
      components = [{ 'id' => "h#{i}", 'type' => 'TextBody', 'props' => { 'text' => "Paso #{i}" } }]
      components << if terminal
                       footer('Enviar', { 'name' => 'complete' })
                     else
                       footer('Siguiente', { 'name' => 'navigate', 'next' => "screen_#{i + 1}" })
                     end
      { 'id' => "screen_#{i}", 'title' => "Paso #{i}", 'terminal' => terminal, 'order' => i, 'components' => components }
    end
    result = described_class.new(flow_with(screens)).call
    expect(result[:valid]).to be(true)
    expect(screens.size).to eq(7)
  end

  # Caso 4: variables referenciando una pantalla anterior — válido.
  it 'accepts a variable reference to a field on a previous screen' do
    screens = [
      { 'id' => 'q1', 'title' => 'Pregunta 1', 'terminal' => false, 'order' => 0,
        'components' => [
          { 'id' => 't1', 'type' => 'TextInput', 'props' => { 'name' => 'nombre', 'label' => 'Nombre' } },
          footer('Siguiente', { 'name' => 'navigate', 'next' => 'q2' })
        ] },
      { 'id' => 'q2', 'title' => 'Pregunta 2', 'terminal' => true, 'order' => 1,
        'components' => [
          { 'id' => 'b1', 'type' => 'TextBody', 'props' => { 'text' => 'Hola ${screen.q1.form.nombre}, gracias' } },
          footer('Enviar', { 'name' => 'complete' })
        ] }
    ]
    result = described_class.new(flow_with(screens)).call
    expect(result[:valid]).to be(true)
  end

  # Caso 5a: error deliberado — referencia a variable de pantalla posterior/inexistente.
  it 'rejects a variable reference to a field on a LATER (or unknown) screen' do
    screens = [
      { 'id' => 'q1', 'title' => 'Pregunta 1', 'terminal' => false, 'order' => 0,
        'components' => [
          { 'id' => 'b1', 'type' => 'TextBody', 'props' => { 'text' => 'Hola ${screen.q2.form.nombre}' } },
          footer('Siguiente', { 'name' => 'navigate', 'next' => 'q2' })
        ] },
      { 'id' => 'q2', 'title' => 'Pregunta 2', 'terminal' => true, 'order' => 1,
        'components' => [
          { 'id' => 't1', 'type' => 'TextInput', 'props' => { 'name' => 'nombre', 'label' => 'Nombre' } },
          footer('Enviar', { 'name' => 'complete' })
        ] }
    ]
    result = described_class.new(flow_with(screens)).call
    expect(result[:valid]).to be(false)
    expect(result[:errors].map { |e| e[:field] }).to include('variable')
  end

  # Caso 5b: error deliberado — sin pantalla terminal.
  it 'rejects a flow with no terminal screen' do
    screens = [
      { 'id' => 'q1', 'title' => 'Pregunta', 'terminal' => false, 'order' => 0,
        'components' => [footer('Siguiente', { 'name' => 'navigate', 'next' => 'q1' })] }
    ]
    result = described_class.new(flow_with(screens)).call
    expect(result[:valid]).to be(false)
    expect(result[:errors]).not_to be_empty
  end

  # Caso 5c: error deliberado — navegación a pantalla inexistente.
  it 'rejects a Footer navigate action pointing at a non-existent screen' do
    screens = [
      { 'id' => 'q1', 'title' => 'Pregunta', 'terminal' => false, 'order' => 0,
        'components' => [footer('Siguiente', { 'name' => 'navigate', 'next' => 'ghost' })] },
      { 'id' => 'q2', 'title' => 'Final', 'terminal' => true, 'order' => 1,
        'components' => [footer('Enviar', { 'name' => 'complete' })] }
    ]
    result = described_class.new(flow_with(screens)).call
    expect(result[:valid]).to be(false)
    expect(result[:errors].map { |e| e[:field] }).to include('footer.action.next')
  end

  # Caso 5d: error deliberado — id 'SUCCESS' reservado, componente desconocido, límite de OptIn.
  it 'rejects a reserved SUCCESS screen id, an unknown component type, and exceeding per-screen limits' do
    optin_components = (1..6).map { |i| { 'id' => "o#{i}", 'type' => 'OptIn', 'props' => { 'name' => "opt#{i}", 'label' => 'Acepto' } } }
    screens = [
      { 'id' => 'SUCCESS', 'title' => 'Malo', 'terminal' => true, 'order' => 0,
        'components' => optin_components + [
          { 'id' => 'x1', 'type' => 'DoesNotExist', 'props' => {} },
          footer('Enviar', { 'name' => 'complete' })
        ] }
    ]
    result = described_class.new(flow_with(screens)).call
    expect(result[:valid]).to be(false)
    fields_and_messages = result[:errors].map { |e| e[:message] }.join(' | ')
    expect(fields_and_messages).to match(/reservado/)
    expect(fields_and_messages).to match(/no soportado/)
    expect(fields_and_messages).to match(/OptIn/)
  end

  it 'rejects a blank name and an invalid category' do
    flow = account.jabvox_whatsapp_flows.new(inbox: inbox, waba_id: '123', name: '', category: 'BOGUS')
    flow.save(validate: false)
    result = described_class.new(flow).call
    expect(result[:valid]).to be(false)
    fields = result[:errors].map { |e| e[:field] }
    expect(fields).to include('name')
    expect(fields).to include('category')
  end

  it 'rejects duplicate screen ids' do
    screens = [
      { 'id' => 'dup', 'title' => 'A', 'terminal' => true, 'order' => 0, 'components' => [footer('Enviar', { 'name' => 'complete' })] },
      { 'id' => 'dup', 'title' => 'B', 'terminal' => true, 'order' => 1, 'components' => [footer('Enviar', { 'name' => 'complete' })] }
    ]
    result = described_class.new(flow_with(screens)).call
    expect(result[:valid]).to be(false)
    expect(result[:errors].map { |e| e[:message] }.join).to match(/duplicado/)
  end
end
