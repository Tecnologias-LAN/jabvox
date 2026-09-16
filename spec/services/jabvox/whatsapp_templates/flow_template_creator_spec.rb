require 'rails_helper'

# Crear el Flow y la plantilla en un solo paso desde el wizard. Meta exige que
# el Flow exista y esté publicado ANTES de que la plantilla lo referencie.
RSpec.describe Jabvox::WhatsappTemplates::FlowTemplateCreator do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                              sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:creator) { described_class.new(account) }

  let(:screens) do
    [
      { 'id' => 'welcome', 'title' => 'Inicio', 'terminal' => false, 'order' => 0,
        'components' => [
          { 'id' => 'c1', 'type' => 'TextHeading', 'props' => { 'text' => 'Encuesta' } },
          { 'id' => 'c2', 'type' => 'Footer',
            'props' => { 'label' => 'Siguiente', 'action' => { 'name' => 'navigate', 'next' => 'end' } } }
        ] },
      { 'id' => 'end', 'title' => 'Fin', 'terminal' => true, 'order' => 1,
        'components' => [
          { 'id' => 'c3', 'type' => 'TextArea', 'props' => { 'name' => 'comentario', 'label' => 'Comentario' } },
          { 'id' => 'c4', 'type' => 'Footer', 'props' => { 'label' => 'Enviar', 'action' => { 'name' => 'complete' } } }
        ] }
    ]
  end

  let(:params) do
    {
      name: 'encuesta_satisfaccion', category: 'MARKETING', language: 'es',
      body: 'Hola, cuéntanos tu experiencia por favor',
      template_kind: 'flow', flow_button_text: 'Responder',
      flow: { screens_json: screens, category: 'SURVEY' }
    }
  end

  def stub_flow_publish(meta_flow_id: 'flow-123')
    publish = instance_double(Jabvox::WhatsappFlows::PublishService)
    allow(Jabvox::WhatsappFlows::PublishService).to receive(:new).and_return(publish)
    allow(publish).to receive(:call) do
      flow = account.jabvox_whatsapp_flows.last
      flow.update!(meta_flow_id: meta_flow_id, status: 'published', meta_status: 'PUBLISHED')
      { success: true, flow: flow }
    end
  end

  describe 'camino feliz' do
    before do
      stub_flow_publish
      allow_any_instance_of(Jabvox::WhatsappTemplatesManager) # rubocop:disable RSpec/AnyInstance
        .to receive(:create) do |_m, _inbox, tpl_params|
          { success: true,
            template: account.jabvox_whatsapp_templates.create!(
              inbox: inbox, name: tpl_params[:name], language: 'es', category: 'MARKETING',
              status: 'PENDING', template_kind: 'flow', buttons_json: tpl_params[:buttons],
              variables_json: {}, meta_json: {}
            ) }
        end
    end

    it 'crea el Flow con las pantallas recibidas' do
      creator.call(inbox, params)

      flow = account.jabvox_whatsapp_flows.last
      expect(flow.screens_json.size).to eq(2)
      expect(flow.category).to eq('SURVEY')
    end

    it 'nombra el Flow como la plantilla cuando no se le da nombre propio' do
      creator.call(inbox, params)

      expect(account.jabvox_whatsapp_flows.last.name).to eq('encuesta_satisfaccion')
    end

    it 'deja la plantilla con un botón FLOW apuntando al id de Meta' do
      result = creator.call(inbox, params)

      button = result[:template].buttons_json.first.with_indifferent_access
      expect(button[:type]).to eq('FLOW')
      expect(button[:flow_id]).to eq('flow-123')
      expect(button[:text]).to eq('Responder')
    end

    it 'abre el Flow en su primera pantalla' do
      result = creator.call(inbox, params)

      button = result[:template].buttons_json.first.with_indifferent_access
      expect(button[:navigate_screen]).to eq('welcome')
    end

    # Meta exige nombres únicos dentro del WABA y el usuario no elige el del
    # Flow (lo hereda de la plantilla), así que un reintento chocaba con
    # "Flow name is not unique".
    it 'evita chocar con el nombre de un Flow que ya existe en la bandeja' do
      account.jabvox_whatsapp_flows.create!(
        inbox: inbox, waba_id: '1', name: 'encuesta_satisfaccion',
        category: 'SURVEY', status: 'draft', screens_json: screens
      )

      creator.call(inbox, params)

      expect(account.jabvox_whatsapp_flows.pluck(:name))
        .to contain_exactly('encuesta_satisfaccion', 'encuesta_satisfaccion_2')
    end

    it 'enlaza la plantilla con el Flow' do
      result = creator.call(inbox, params)

      expect(result[:template].reload.jabvox_whatsapp_flow_id).to eq(account.jabvox_whatsapp_flows.last.id)
    end
  end

  describe 'errores' do
    it 'exige la definición del formulario' do
      result = creator.call(inbox, params.merge(flow: {}))

      expect(result[:success]).to be(false)
      expect(result[:error]).to include('flow')
    end

    # Lo importante es no dejar una plantilla huérfana apuntando a un Flow que
    # Meta nunca aceptó.
    it 'no crea la plantilla si el Flow no se pudo publicar' do
      publish = instance_double(Jabvox::WhatsappFlows::PublishService)
      allow(Jabvox::WhatsappFlows::PublishService).to receive(:new).and_return(publish)
      allow(publish).to receive(:call).and_return({ success: false, error: 'pantalla inválida' })

      result = creator.call(inbox, params)

      expect(result[:success]).to be(false)
      expect(result[:error]).to include('pantalla inválida')
      expect(account.jabvox_whatsapp_templates.count).to eq(0)
    end

    it 'conserva el Flow como borrador para poder retomarlo' do
      publish = instance_double(Jabvox::WhatsappFlows::PublishService)
      allow(Jabvox::WhatsappFlows::PublishService).to receive(:new).and_return(publish)
      allow(publish).to receive(:call).and_return({ success: false, error: 'falló' })

      result = creator.call(inbox, params)

      expect(account.jabvox_whatsapp_flows.count).to eq(1)
      expect(result[:error]).to include('borrador')
    end
  end
end
