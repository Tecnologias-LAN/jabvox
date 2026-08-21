# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::Billing::Gateways::Bold do
  let(:secret) { 'events-secret-abc' }
  # Secretos y modo se administran desde el Super Admin (BD), ya no por ENV.
  let(:config) do
    create(:jabvox_payment_gateway_config, provider: 'bold', active: true,
                                           sandbox: false, secret_key: secret)
  end
  let(:gateway) { described_class.new(config) }
  let(:raw_body) { '{"type":"SALE_APPROVED","data":{"metadata":{"reference":"ref-1"}}}' }

  # Firma oficial de Bold: base64(cuerpo) -> HMAC-SHA256 con la llave secreta -> HEX.
  def bold_signature(body, key)
    OpenSSL::HMAC.hexdigest('SHA256', key, Base64.strict_encode64(body))
  end

  def request_with(signature)
    instance_double(ActionDispatch::Request, headers: { 'x-bold-signature' => signature })
  end

  describe '#verify_webhook_signature (producción)' do
    it 'acepta la firma correcta (base64 -> HMAC-SHA256 -> hex)' do
      valid = bold_signature(raw_body, secret)
      expect(gateway.verify_webhook_signature(request_with(valid), raw_body)).to be(true)
    end

    it 'rechaza una firma incorrecta' do
      expect(gateway.verify_webhook_signature(request_with('firma-mala'), raw_body)).to be(false)
    end

    it 'rechaza cuando no viene firma' do
      expect(gateway.verify_webhook_signature(request_with(nil), raw_body)).to be(false)
    end

    it 'rechaza una firma en base64 (formato viejo/incorrecto), no en hex' do
      wrong = Base64.strict_encode64(OpenSSL::HMAC.digest('SHA256', secret, raw_body))
      expect(gateway.verify_webhook_signature(request_with(wrong), raw_body)).to be(false)
    end

    it 'rechaza (levanta) si la secret_key no está configurada en el Super Admin' do
      config.update!(secret_key: nil)
      expect do
        gateway.verify_webhook_signature(request_with('x'), raw_body)
      end.to raise_error(Jabvox::Billing::Gateways::GatewayError)
    end
  end

  describe '#verify_webhook_signature (sandbox: secreto vacío)' do
    let(:config) do
      create(:jabvox_payment_gateway_config, provider: 'bold', active: true, sandbox: true)
    end

    it 'usa cadena vacía como secreto en sandbox' do
      valid = bold_signature(raw_body, '')
      expect(gateway.verify_webhook_signature(request_with(valid), raw_body)).to be(true)
    end
  end

  describe '#parse_webhook_event' do
    it 'normaliza un evento aprobado' do
      payload = JSON.parse(
        '{"type":"SALE_APPROVED","data":{"payment_id":"P1","metadata":{"reference":"ref-1"},' \
        '"amount":{"total":50000,"currency":"COP"}}}'
      )
      event = gateway.parse_webhook_event(payload)

      expect(event[:approved]).to be(true)
      expect(event[:reference]).to eq('ref-1')
      expect(event[:payment_id]).to eq('P1')
      expect(event[:amount_cents]).to eq(5_000_000) # 50000 COP -> centavos
    end

    it 'marca rechazado un SALE_REJECTED' do
      event = gateway.parse_webhook_event(JSON.parse('{"type":"SALE_REJECTED","data":{}}'))
      expect(event[:approved]).to be(false)
      expect(event[:rejected]).to be(true)
    end
  end
end
