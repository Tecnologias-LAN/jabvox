require 'rails_helper'

# Un mensaje de sesión que revienta en la app (payload inválido, fallo de red) se quedaba
# en "sent" sin source_id: el relojito eterno en la conversación, sin pista de por qué.
# El camino de plantillas ya estaba protegido; este no.
describe Whatsapp::SendOnWhatsappService do
  let!(:whatsapp_channel) { create(:channel_whatsapp, sync_templates: false, validate_provider_config: false) }
  let!(:contact_inbox) { create(:contact_inbox, inbox: whatsapp_channel.inbox, source_id: '123456789') }
  let!(:conversation) { create(:conversation, contact_inbox: contact_inbox, inbox: whatsapp_channel.inbox) }
  let(:message) do
    create(:message, message_type: :outgoing, content: 'hola',
                     conversation: conversation, inbox: whatsapp_channel.inbox, account: whatsapp_channel.account)
  end

  # La ventana de 24h debe estar abierta: si no, el servicio corta antes de llegar al
  # envío de sesión y el spec no probaría nada.
  before { allow_any_instance_of(Conversation).to receive(:can_reply?).and_return(true) } # rubocop:disable RSpec/AnyInstance

  it 'marks the message as failed and says the failure was on our side' do
    allow(whatsapp_channel).to receive(:send_message).and_raise(StandardError, 'connection reset')
    allow_any_instance_of(described_class).to receive(:channel).and_return(whatsapp_channel) # rubocop:disable RSpec/AnyInstance

    described_class.new(message: message).perform

    expect(message.reload.status).to eq('failed')
    expect(message.reload.external_error).to include('No se pudo enviar desde Jabvox')
    expect(message.reload.external_error).to include('connection reset')
  end

  it 'never leaves the message silently in sent' do
    allow(whatsapp_channel).to receive(:send_message).and_raise(ArgumentError, 'bad payload')
    allow_any_instance_of(described_class).to receive(:channel).and_return(whatsapp_channel) # rubocop:disable RSpec/AnyInstance

    described_class.new(message: message).perform

    expect(message.reload.status).not_to eq('sent')
  end
end
