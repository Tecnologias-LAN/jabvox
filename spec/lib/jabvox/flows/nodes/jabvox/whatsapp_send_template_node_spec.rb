# frozen_string_literal: true

require 'rails_helper'
require_relative '../spec_helper_nodes'

# jabvox.whatsapp.send_template — el nodo más delicado. NUNCA envía de verdad:
# `SendReplyJob` se dobla, así que lo que se prueba es la decisión del nodo.
RSpec.describe Jabvox::Flows::Nodes::Jabvox::WhatsappSendTemplateNode do
  include NodeSpecHelpers

  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+573001112233') }
  let(:ctx) { build_ctx(account) }

  # Por defecto el envío "sale bien": el mensaje se queda como `sent`.
  before { allow(SendReplyJob).to receive(:perform_now) }

  def crear_plantilla(**attrs)
    account.jabvox_whatsapp_templates.create!(
      { inbox: inbox, name: 'recordatorio', language: 'es', category: 'UTILITY', status: 'APPROVED',
        body_content: 'Hola {{1}}, tu cita es el {{2}}.', buttons_json: [], variables_json: {},
        meta_json: {} }.merge(attrs)
    )
  end

  def enviar(params = {})
    run_node(described_class, ctx,
             { 'inbox' => inbox.id, 'contactId' => contact.id, 'template' => 'recordatorio' }.merge(params))
  end

  describe 'envío correcto' do
    it 'envía la plantilla resolviendo los huecos del cuerpo' do
      crear_plantilla
      result = enviar('variableMap' => { '1' => 'nombre', '2' => 'text:mañana' })

      expect(result).to be_ok
      expect(result.output['processedParams']).to eq('1' => contact.name, '2' => 'mañana')
      expect(result.output['content']).to eq("Hola #{contact.name}, tu cita es el mañana.")
    end

    it 'envía una plantilla SIN variables' do
      crear_plantilla(body_content: 'Tu pedido ha sido enviado.')

      result = enviar

      expect(result).to be_ok
      expect(result.output['processedParams']).to eq({})
      expect(result.output['slots']).to eq([])
    end

    it 'guarda template_params en el mensaje, que es lo que lee el canal' do
      crear_plantilla
      result = enviar('variableMap' => { '1' => 'text:Ana', '2' => 'text:hoy' })

      params = Message.find(result.output['messageId']).additional_attributes['template_params']
      expect(params).to include('name' => 'recordatorio', 'language' => 'es', 'category' => 'UTILITY')
    end

    it 'REUTILIZA la conversación existente del contacto en esa bandeja' do
      crear_plantilla(body_content: 'Hola.')
      existente = create(:conversation, account: account, inbox: inbox, contact: contact)

      result = enviar

      expect(result.output['conversationId']).to eq(existente.display_id)
    end
  end

  describe 'idioma vacío (el bug que Meta rechazaba)' do
    it "cae al idioma de la PLANTILLA cuando llega '', no a un idioma vacío" do
      crear_plantilla(language: 'es_CO', body_content: 'Hola.')

      result = enviar('language' => '')

      expect(result.output['language']).to eq('es_CO')
    end

    it "usa 'es' cuando no hay plantilla ni idioma configurado" do
      result = enviar('language' => '', 'template' => 'inexistente')

      expect(result.output['language']).to eq('es')
    end
  end

  describe 'falso éxito de WhatsApp (el bug de producción)' do
    it 'FALLA el paso cuando Meta rechaza, aunque el mensaje se creara' do
      crear_plantilla(body_content: 'Hola.')
      # Así se comporta el canal real ante un rechazo de Meta.
      allow(SendReplyJob).to receive(:perform_now) do |message_id|
        Message.find(message_id).update!(status: :failed, external_error: 'Template not found')
      end

      result = enviar

      expect(result).not_to be_ok
      expect(result.error).to match(/Meta RECHAZÓ/)
      expect(result.error).to include('Template not found')
    end

    it 'no declara entrega confirmada mientras el mensaje solo está «sent»' do
      crear_plantilla(body_content: 'Hola.')

      result = enviar

      expect(result.output['delivery']).to eq('sent')
      expect(result.output['deliveryConfirmed']).to be(false)
    end
  end

  describe 'validaciones previas' do
    it 'rechaza un contacto SIN teléfono antes de intentar enviar' do
      crear_plantilla(body_content: 'Hola.')
      sin_telefono = create(:contact, account: account, phone_number: nil)

      result = enviar('contactId' => sin_telefono.id)

      expect(result.error).to match(/NO tiene número de teléfono/)
      expect(SendReplyJob).not_to have_received(:perform_now)
    end

    it 'dice CUÁNTOS y CUÁLES huecos faltan en vez de dejar fallar a Meta' do
      crear_plantilla

      result = enviar('variableMap' => { '1' => 'nombre' })

      expect(result.error).to match(/necesita 2 valor\(es\) y faltan 1/)
      expect(result.error).to include('{{2}}')
    end

    it 'rechaza una plantilla que Meta no ha aprobado' do
      crear_plantilla(status: 'PENDING', body_content: 'Hola.')

      expect(enviar.error).to match(/está en estado PENDING/)
    end

    it 'rechaza una bandeja que no es de WhatsApp API oficial' do
      otra = create(:inbox, account: account)

      expect(enviar('inbox' => otra.id).error).to match(/no es una bandeja de WhatsApp API oficial/)
    end

    it 'exige la plantilla' do
      expect(enviar('template' => '').error).to match(/Falta la "Plantilla"/)
    end

    it 'no alcanza un contacto de otra cuenta' do
      ajeno = create(:contact, account: create(:account), phone_number: '+573009998877')

      expect(enviar('contactId' => ajeno.id).error).to match(/no existe en esta cuenta/)
    end
  end

  describe 'cabecera y botones' do
    it 'manda la cabecera media en template_components' do
      crear_plantilla(header_type: 'IMAGE', body_content: 'Hola.')

      result = enviar('variableMap' => { 'header_media' => 'text:https://ej.com/i.png' })

      components = Message.find(result.output['messageId'])
                          .additional_attributes.dig('template_params', 'template_components')
      expect(components.first).to include('type' => 'header')
      expect(components.first['parameters'].first.dig('image', 'link')).to eq('https://ej.com/i.png')
    end

    it 'exige la URL de la cabecera media si no se rellena' do
      crear_plantilla(header_type: 'IMAGE', body_content: 'Hola.')

      expect(enviar.error).to match(/URL de la imagen de cabecera/)
    end

    it 'manda el sufijo dinámico de un botón URL' do
      crear_plantilla(body_content: 'Hola.', buttons_json: [{ 'type' => 'URL', 'text' => 'Ver',
                                                              'url' => 'https://ej.com/p/{{1}}' }])

      result = enviar('variableMap' => { 'button_0_url' => 'text:ABC' })

      components = Message.find(result.output['messageId'])
                          .additional_attributes.dig('template_params', 'template_components')
      expect(components.first).to include('type' => 'button', 'sub_type' => 'url')
      expect(components.first['parameters'].first['text']).to eq('ABC')
    end

    it 'NO añade template_components cuando la plantilla no los necesita' do
      crear_plantilla(body_content: 'Hola.')

      result = enviar

      expect(Message.find(result.output['messageId']).additional_attributes['template_params'])
        .not_to have_key('template_components')
    end
  end
end
