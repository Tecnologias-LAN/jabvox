require 'rails_helper'

# El nodo de Automations no sabía enviar plantillas con botón FLOW (fallaba con
# "#131009" al ejecutar el flujo) ni con COPY_CODE. Estos specs cubren ese gap.
# Ver docs/whatsapp-flows/templates-sending-architecture.md.
RSpec.describe Jabvox::Flows::Nodes::WhatsappTemplatePayload do
  let(:structure_mod) { Jabvox::Flows::Nodes::WhatsappTemplateStructure }

  describe 'botón FLOW' do
    let(:template) do
      { 'name' => 'encuesta', 'language' => 'es', 'body_content' => 'Hola, cuéntanos tu opinión',
        'components' => [
          { 'type' => 'BODY', 'text' => 'Hola, cuéntanos tu opinión' },
          { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'FLOW', 'text' => 'Comenzar', 'flow_id' => '9988' }] }
        ] }
    end
    let(:structure) { structure_mod.parse(template) }

    it 'reconoce el botón como tipo flow' do
      expect(structure['buttons'].first['type']).to eq('flow')
    end

    it 'no le pide ningún valor al usuario (el flow_token se genera solo)' do
      flow_slots = structure['slots'].select { |s| s['scope'] == 'button' }
      expect(flow_slots).to be_empty
    end

    it 'emite el componente action que Meta exige, con un flow_token presente' do
      components = described_class.components(structure, {})

      button = components.find { |c| c['sub_type'] == 'flow' }
      expect(button['type']).to eq('button')
      expect(button['index']).to eq(0)
      action = button['parameters'].first['action']
      expect(action['flow_token']).to be_present
      expect(action['flow_action_data']).to eq({})
    end

    it 'genera un flow_token distinto en cada envío' do
      first = described_class.components(structure, {}).first['parameters'].first['action']['flow_token']
      second = described_class.components(structure, {}).first['parameters'].first['action']['flow_token']

      expect(first).not_to eq(second)
    end
  end

  describe 'botón COPY_CODE' do
    let(:template) do
      { 'name' => 'cupon', 'language' => 'es', 'body_content' => 'Tu cupón está listo',
        'components' => [
          { 'type' => 'BODY', 'text' => 'Tu cupón está listo' },
          { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'COPY_CODE', 'text' => 'Copiar' }] }
        ] }
    end
    let(:structure) { structure_mod.parse(template) }

    it 'pide el código como un hueco obligatorio' do
      slot = structure['slots'].find { |s| s['key'] == 'button_0_copy_code' }

      expect(slot).to be_present
      expect(slot['required']).to be(true)
    end

    it 'emite el parámetro coupon_code con el valor recibido' do
      components = described_class.components(structure, { 'button_0_copy_code' => 'VERANO25' })

      button = components.find { |c| c['sub_type'] == 'copy_code' }
      expect(button['parameters']).to eq([{ 'type' => 'coupon_code', 'coupon_code' => 'VERANO25' }])
    end

    it 'reporta el hueco como faltante si no se rellenó' do
      missing = structure_mod.missing_slots(structure, {})

      expect(missing.map { |s| s['key'] }).to include('button_0_copy_code')
    end
  end

  describe 'regresión: botones ya soportados' do
    it 'sigue emitiendo quick_reply y url dinámica como antes' do
      template = { 'name' => 'mix', 'language' => 'es', 'body_content' => 'Hola',
                   'components' => [
                     { 'type' => 'BODY', 'text' => 'Hola' },
                     { 'type' => 'BUTTONS', 'buttons' => [
                       { 'type' => 'URL', 'text' => 'Ver', 'url' => 'https://x.com/{{1}}' },
                       { 'type' => 'QUICK_REPLY', 'text' => 'Sí', 'payload' => 'yes' }
                     ] }
                   ] }
      structure = structure_mod.parse(template)

      components = described_class.components(
        structure, { 'button_0_url' => 'abc', 'button_1_payload' => 'yes' }
      )

      expect(components.map { |c| c['sub_type'] }).to contain_exactly('url', 'quick_reply')
    end

    it 'no emite componentes de botón para una plantilla sin botones dinámicos' do
      template = { 'name' => 'simple', 'language' => 'es', 'body_content' => 'Hola {{1}}',
                   'components' => [{ 'type' => 'BODY', 'text' => 'Hola {{1}}' }] }
      structure = structure_mod.parse(template)

      expect(described_class.components(structure, { '1' => 'Pablo' })).to be_nil
    end
  end
end
