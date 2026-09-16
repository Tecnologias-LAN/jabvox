require 'rails_helper'

# Cobertura de los tipos de plantilla que el camino estándar no manejaba y que
# ahora se delegan a Jabvox::WhatsappTemplates::SendComponentsBuilder desde el
# canal 1:1 / Leads / Kanban (los tres comparten este servicio).
# Ver docs/whatsapp-flows/templates-sending-architecture.md.
describe Whatsapp::TemplateProcessorService do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }

  def build_service(template_params)
    described_class.new(channel: channel, template_params: template_params, message: nil)
  end

  def components_for(template_params)
    build_service(template_params).call[3]
  end

  before do
    channel.update_column(:message_templates, [template]) # rubocop:disable Rails/SkipsModelValidations -- solo setup del fixture
  end

  describe 'plantilla AUTHENTICATION (botón OTP)' do
    let(:template) do
      {
        'name' => 'otp_login', 'language' => 'es', 'status' => 'approved',
        'category' => 'AUTHENTICATION',
        'components' => [
          { 'type' => 'BODY', 'add_security_recommendation' => true },
          { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'OTP', 'otp_type' => 'COPY_CODE' }] }
        ]
      }
    end

    it 'manda el mismo código en el body y en el botón copy_code' do
      components = components_for(
        'name' => 'otp_login', 'language' => 'es',
        'processed_params' => { 'auth_code' => '123456' }
      )

      expect(components).to eq(
        [
          { type: 'body', parameters: [{ type: 'text', text: '123456' }] },
          { type: 'button', sub_type: 'copy_code', index: '0',
            parameters: [{ type: 'coupon_code', coupon_code: '123456' }] }
        ]
      )
    end

    # El frontend manda un único campo "código"; puede llegar como primer valor
    # del body en lugar de como auth_code explícito.
    it 'acepta el código como primer valor del body' do
      components = components_for(
        'name' => 'otp_login', 'language' => 'es',
        'processed_params' => { 'body' => { '1' => '987654' } }
      )

      expect(components.first[:parameters].first[:text]).to eq('987654')
      expect(components.last[:parameters].first[:coupon_code]).to eq('987654')
    end

    it 'falla con un error legible si no llega el código' do
      expect do
        components_for('name' => 'otp_login', 'language' => 'es', 'processed_params' => {})
      end.to raise_error(ArgumentError, /auth_code/)
    end
  end

  describe 'header LOCATION' do
    let(:template) do
      {
        'name' => 'delivery_location', 'language' => 'es', 'status' => 'approved',
        'components' => [
          { 'type' => 'HEADER', 'format' => 'LOCATION' },
          { 'type' => 'BODY', 'text' => 'Tu pedido llega a {{1}}' }
        ]
      }
    end

    it 'arma el componente header con lat/long/nombre/dirección' do
      components = components_for(
        'name' => 'delivery_location', 'language' => 'es',
        'processed_params' => {
          'body' => { '1' => 'hoy' },
          'location' => { 'latitude' => 4.711, 'longitude' => -74.0721,
                          'name' => 'Sucursal Centro', 'address' => 'Cra 7 #1-10' }
        }
      )

      header = components.find { |c| c[:type] == 'header' }
      expect(header[:parameters]).to eq(
        [{ type: 'location', location: { latitude: 4.711, longitude: -74.0721,
                                         name: 'Sucursal Centro', address: 'Cra 7 #1-10' } }]
      )
    end

    it 'sigue enviando el body junto al header de ubicación' do
      components = components_for(
        'name' => 'delivery_location', 'language' => 'es',
        'processed_params' => {
          'body' => { '1' => 'hoy' },
          'location' => { 'latitude' => 4.711, 'longitude' => -74.0721 }
        }
      )

      body = components.find { |c| c[:type] == 'body' }
      expect(body[:parameters]).to eq([{ type: 'text', text: 'hoy' }])
    end

    it 'falla con error legible si faltan las coordenadas' do
      expect do
        components_for(
          'name' => 'delivery_location', 'language' => 'es',
          'processed_params' => { 'body' => { '1' => 'hoy' } }
        )
      end.to raise_error(ArgumentError, /LOCATION/)
    end
  end

  describe 'plantilla CAROUSEL' do
    let(:template) do
      {
        'name' => 'promo_carousel', 'language' => 'es', 'status' => 'approved',
        'components' => [
          { 'type' => 'BODY', 'text' => 'Hola {{1}}, mira estas ofertas' },
          { 'type' => 'CAROUSEL', 'cards' => [
            { 'components' => [
              { 'type' => 'HEADER', 'format' => 'IMAGE' },
              { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'QUICK_REPLY', 'text' => 'Ver' }] }
            ] },
            { 'components' => [
              { 'type' => 'HEADER', 'format' => 'IMAGE' },
              { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'QUICK_REPLY', 'text' => 'Ver' }] }
            ] }
          ] }
        ]
      }
    end

    let(:processed_params) do
      {
        'body' => { '1' => 'Pablo' },
        'cards' => [
          { 'header' => { 'media_id' => 'media-0' }, 'buttons' => [{ 'index' => 0, 'parameter' => 'card-0' }] },
          { 'header' => { 'media_id' => 'media-1' }, 'buttons' => [{ 'index' => 0, 'parameter' => 'card-1' }] }
        ]
      }
    end

    it 'emite el componente carousel con card_index por card, junto al body' do
      components = components_for(
        'name' => 'promo_carousel', 'language' => 'es', 'processed_params' => processed_params
      )

      expect(components.find { |c| c[:type] == 'body' }[:parameters]).to eq([{ type: 'text', text: 'Pablo' }])
      carousel = components.find { |c| c[:type] == 'carousel' }
      expect(carousel[:cards].map { |c| c[:card_index] }).to eq([0, 1])
      expect(carousel[:cards].first[:components]).to include(
        { type: 'button', sub_type: 'quick_reply', index: '0',
          parameters: [{ type: 'payload', payload: 'card-0' }] }
      )
    end

    it 'falla si la cantidad de cards no coincide con la plantilla' do
      expect do
        components_for(
          'name' => 'promo_carousel', 'language' => 'es',
          'processed_params' => processed_params.merge('cards' => [processed_params['cards'].first])
        )
      end.to raise_error(ArgumentError, /card/)
    end
  end

  describe 'LIMITED_TIME_OFFER' do
    let(:template) do
      {
        'name' => 'lto_promo', 'language' => 'es', 'status' => 'approved',
        'category' => 'MARKETING',
        'components' => [
          { 'type' => 'BODY', 'text' => 'Oferta para {{1}}' },
          { 'type' => 'LIMITED_TIME_OFFER' }
        ]
      }
    end

    it 'emite el componente con expiration_time_ms junto al body' do
      components = components_for(
        'name' => 'lto_promo', 'language' => 'es',
        'processed_params' => { 'body' => { '1' => 'Pablo' }, 'lto_expiration_ms' => 1_735_689_600_000 }
      )

      lto = components.find { |c| c[:type] == 'limited_time_offer' }
      expect(lto[:parameters]).to eq(
        [{ type: 'limited_time_offer', limited_time_offer: { expiration_time_ms: 1_735_689_600_000 } }]
      )
    end

    it 'falla si no llega la expiración' do
      expect do
        components_for(
          'name' => 'lto_promo', 'language' => 'es',
          'processed_params' => { 'body' => { '1' => 'Pablo' } }
        )
      end.to raise_error(ArgumentError, /lto_expiration_ms/)
    end
  end

  describe 'regresión: plantillas estándar siguen intactas' do
    let(:template) do
      {
        'name' => 'standard_tpl', 'language' => 'es', 'status' => 'approved',
        'components' => [
          { 'type' => 'BODY', 'text' => 'Hola {{1}}' },
          { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'QUICK_REPLY', 'text' => 'Sí' }] }
        ]
      }
    end

    it 'no emite componentes extendidos cuando la plantilla no los declara' do
      components = components_for(
        'name' => 'standard_tpl', 'language' => 'es',
        'processed_params' => { 'body' => { '1' => 'Pablo' } }
      )

      expect(components.map { |c| c[:type] }).to eq(['body'])
      expect(components.first[:parameters]).to eq([{ type: 'text', text: 'Pablo' }])
    end
  end
end
