# frozen_string_literal: true

require 'rails_helper'
require_relative '../spec_helper_nodes'

RSpec.describe Jabvox::Flows::Nodes::Jabvox::SmsSendNode do
  include NodeSpecHelpers

  let(:account) { create(:account) }
  let(:ctx) { build_ctx(account) }
  let(:provider) do
    account.jabvox_sms_providers.create!(name: 'Voziphone', base_url: 'https://sms.ej.com',
                                         api_user: 'u', api_password: 'p')
  end
  let(:contact) { create(:contact, account: account, name: 'Ana', phone_number: '+573001112233') }
  let(:params) { { 'providerId' => provider.id, 'contactId' => contact.id, 'message' => 'Hola Ana' } }

  # NUNCA sale un SMS real: se simula la fila que crea el servicio.
  def stub_send(status:, error: nil)
    sms = account.jabvox_sms_messages.create!(
      jabvox_sms_provider: provider, contact: contact, phone: '573001112233',
      message: 'Hola Ana', status: status, error_message: error
    )
    allow_any_instance_of(Jabvox::SmsSenderService).to receive(:send_sms).and_return(sms) # rubocop:disable RSpec/AnyInstance
    sms
  end

  it 'envía el SMS y publica el estado real del mensaje' do
    sms = stub_send(status: 'sent')

    result = run_node(described_class, ctx, params)

    expect(result).to be_ok
    expect(result.output).to include('sent' => true, 'status' => 'sent', 'smsId' => sms.id,
                                     'contact_id' => contact.id, 'provider_id' => provider.id)
  end

  it 'reporta FALLO cuando el proveedor no lo entrega (nada de falso éxito)' do
    stub_send(status: 'failed', error: 'HTTP 401: unauthorized')

    result = run_node(described_class, ctx, params)

    expect(result).not_to be_ok
    expect(result.error).to match(/estado "failed".*HTTP 401: unauthorized/)
  end

  it 'reporta fallo también si el mensaje queda en pendiente' do
    stub_send(status: 'pending')

    expect(run_node(described_class, ctx, params).error).to match(/estado "pending".*sin detalle/)
  end

  it 'falla si el contacto no tiene teléfono' do
    sin_tel = create(:contact, account: account, name: 'Sin tel', phone_number: nil)

    expect(run_node(described_class, ctx, params.merge('contactId' => sin_tel.id)).error)
      .to match(/no tiene número de teléfono/)
  end

  it 'falla si el mensaje llega vacío' do
    expect(run_node(described_class, ctx, params.merge('message' => '   ')).error)
      .to match(/Falta el mensaje del SMS/)
  end

  it 'falla si el proveedor llega vacío' do
    expect(run_node(described_class, ctx, params.merge('providerId' => '')).error)
      .to match(/Falta el proveedor SMS/)
  end

  it 'no acepta un proveedor de OTRA cuenta' do
    ajeno = create(:account).jabvox_sms_providers.create!(name: 'X', base_url: 'https://x.com',
                                                          api_user: 'u', api_password: 'p')

    expect(run_node(described_class, ctx, params.merge('providerId' => ajeno.id)).error)
      .to match(/no existe en esta cuenta/)
  end

  it 'rechaza un proveedor INACTIVO' do
    provider.update!(active: false)

    expect(run_node(described_class, ctx, params).error).to match(/está INACTIVO/)
  end

  it 'no envía a un contacto de OTRA cuenta' do
    ajeno = create(:contact, account: create(:account), phone_number: '+573009998877')

    expect(run_node(described_class, ctx, params.merge('contactId' => ajeno.id)).error)
      .to match(/no existe en esta cuenta/)
  end
end
