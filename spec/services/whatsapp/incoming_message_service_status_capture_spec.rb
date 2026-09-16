require 'rails_helper'

# Captura completa del webhook de status de Meta: pricing, conversation origin y
# procesamiento de TODOS los statuses de un mismo webhook (antes solo se tomaba
# el primero). Ver docs/whatsapp-flows/templates-sending-architecture.md sección 4.
describe Whatsapp::IncomingMessageService do
  let!(:whatsapp_channel) { create(:channel_whatsapp, sync_templates: false, validate_provider_config: false) }
  # source_id único por ejemplo (numérico: el inbox de WhatsApp lo valida así):
  # el servicio deduplica mensajes entrantes por source_id, así que reutilizarlo
  # entre ejemplos haría que el mensaje del `before` no se cree del segundo en adelante.
  let(:from) { rand(100_000_000_000..999_999_999_999).to_s }
  let(:contact_inbox) { create(:contact_inbox, inbox: whatsapp_channel.inbox, source_id: from) }
  let(:inbound_params) do
    {
      'contacts' => [{ 'profile' => { 'name' => 'Sojan Jose' }, 'wa_id' => from }],
      'messages' => [{ 'from' => from, 'id' => from, 'text' => { 'body' => 'Test' },
                       'timestamp' => '1633034394', 'type' => 'text' }]
    }.with_indifferent_access
  end

  def deliver(params)
    described_class.new(inbox: whatsapp_channel.inbox, params: params.with_indifferent_access).perform
  end

  before do
    create(:conversation, inbox: whatsapp_channel.inbox, contact_inbox: contact_inbox, contact: contact_inbox.contact)
    deliver(inbound_params)
  end

  describe 'pricing y conversation del payload de status' do
    it 'persiste category, billable, pricing_model y el origen de la conversación' do
      deliver(
        'statuses' => [{
          'recipient_id' => from, 'id' => from, 'status' => 'delivered', 'timestamp' => '1633034400',
          'conversation' => { 'id' => 'CONV-123', 'origin' => { 'type' => 'business_initiated' } },
          'pricing' => { 'billable' => true, 'pricing_model' => 'PMP', 'category' => 'marketing' }
        }]
      )

      event = MessageStatusEvent.find_by!(message_id: Message.find_by!(source_id: from).id, status: 'delivered')
      expect(event.pricing_category).to eq('marketing')
      expect(event.pricing_billable).to be(true)
      expect(event.pricing_model).to eq('PMP')
      expect(event.whatsapp_conversation_id).to eq('CONV-123')
      expect(event.conversation_origin_type).to eq('business_initiated')
    end

    it 'deja los campos nulos cuando Meta no manda pricing (statuses no facturables)' do
      deliver('statuses' => [{ 'recipient_id' => from, 'id' => from, 'status' => 'read' }])

      event = MessageStatusEvent.find_by!(message_id: Message.find_by!(source_id: from).id, status: 'read')
      expect(event.pricing_category).to be_nil
      expect(event.pricing_billable).to be_nil
      expect(event.conversation_origin_type).to be_nil
    end

    it 'distingue un mensaje gratuito dentro de la ventana de servicio' do
      deliver(
        'statuses' => [{
          'recipient_id' => from, 'id' => from, 'status' => 'delivered',
          'pricing' => { 'billable' => false, 'category' => 'utility' }
        }]
      )

      event = MessageStatusEvent.find_by!(message_id: Message.find_by!(source_id: from).id, status: 'delivered')
      expect(event.pricing_billable).to be(false)
      expect(event.pricing_category).to eq('utility')
    end
  end

  describe 'múltiples statuses en un mismo webhook' do
    # Meta no garantiza orden ni un status por webhook; antes solo se procesaba
    # statuses.first y el resto se perdía en silencio.
    it 'procesa todos los statuses recibidos, no solo el primero' do
      deliver(
        'statuses' => [
          { 'recipient_id' => from, 'id' => from, 'status' => 'delivered', 'timestamp' => '1633034400' },
          { 'recipient_id' => from, 'id' => from, 'status' => 'read', 'timestamp' => '1633034500' }
        ]
      )

      message = Message.find_by!(source_id: from)
      expect(MessageStatusEvent.where(message_id: message.id).pluck(:status)).to contain_exactly('delivered', 'read')
      expect(message.reload.status).to eq('read')
    end

    it 'sigue siendo idempotente si el mismo status llega repetido' do
      status = { 'recipient_id' => from, 'id' => from, 'status' => 'delivered', 'timestamp' => '1633034400' }

      deliver('statuses' => [status])
      deliver('statuses' => [status])

      message = Message.find_by!(source_id: from)
      expect(MessageStatusEvent.where(message_id: message.id, status: 'delivered').count).to eq(1)
    end

    it 'un status inválido no impide procesar los demás del mismo webhook' do
      deliver(
        'statuses' => [
          { 'recipient_id' => from, 'id' => 'wamid.desconocido', 'status' => 'delivered' },
          { 'recipient_id' => from, 'id' => from, 'status' => 'read', 'timestamp' => '1633034500' }
        ]
      )

      message = Message.find_by!(source_id: from)
      expect(message.reload.status).to eq('read')
    end
  end

  describe 'status failed' do
    it 'guarda el código y título de error de Meta junto al evento' do
      deliver(
        'statuses' => [{
          'recipient_id' => from, 'id' => from, 'status' => 'failed', 'timestamp' => '1633034400',
          'errors' => [{ 'code' => 131_049, 'title' => 'Message failed to send' }]
        }]
      )

      message = Message.find_by!(source_id: from)
      event = MessageStatusEvent.find_by!(message_id: message.id, status: 'failed')
      expect(event.error_code).to eq('131049')
      expect(event.error_title).to eq('Message failed to send')
      expect(message.reload.external_error).to eq('131049: Message failed to send')
    end
  end
end
