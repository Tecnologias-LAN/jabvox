require 'rails_helper'

# Los payloads esperados aquí son los verificados contra la documentación de Meta
# y transcritos en docs/whatsapp-flows/templates-sending-architecture.md sección 2.
# Si Meta cambia una forma, este spec es el que debe fallar primero.
RSpec.describe Jabvox::WhatsappTemplates::SendComponentsBuilder do
  def build(meta_components, send_params)
    described_class.call(meta_components: meta_components, send_params: send_params)
  end

  describe 'plantilla de texto simple (regresión)' do
    let(:meta_components) do
      [{ 'type' => 'BODY', 'text' => 'Hola {{1}}, tu pedido {{2}} va en camino.' }]
    end

    it 'arma el componente body con los valores en orden posicional' do
      result = build(meta_components, body_values: { '1' => 'Pablo', '2' => 'A-99' })

      expect(result.success?).to be(true)
      expect(result.components).to eq(
        [{ type: 'body', parameters: [{ type: 'text', text: 'Pablo' }, { type: 'text', text: 'A-99' }] }]
      )
    end

    it 'ordena numéricamente aunque las claves lleguen desordenadas' do
      result = build(meta_components, body_values: { '2' => 'A-99', '1' => 'Pablo' })

      texts = result.components.first[:parameters].map { |p| p[:text] }
      expect(texts).to eq(%w[Pablo A-99])
    end

    it 'usa parameter_name cuando el cuerpo es NAMED' do
      named = [{ 'type' => 'BODY', 'text' => 'Hola {{nombre}}' }]
      result = build(named, body_values: { 'nombre' => 'Pablo' })

      expect(result.components).to eq(
        [{ type: 'body', parameters: [{ type: 'text', parameter_name: 'nombre', text: 'Pablo' }] }]
      )
    end

    it 'no emite componente body si la plantilla no declara BODY' do
      result = build([{ 'type' => 'HEADER', 'format' => 'TEXT' }], body_values: { '1' => 'x' })

      expect(result.components).to eq([])
    end
  end

  describe 'header de media' do
    let(:meta_components) { [{ 'type' => 'HEADER', 'format' => 'IMAGE' }] }

    it 'usa el media_id cuando está disponible' do
      result = build(meta_components, header: { media_id: '1558081531584829' })

      expect(result.components).to eq(
        [{ type: 'header', parameters: [{ :type => 'image', 'image' => { id: '1558081531584829' } }] }]
      )
    end

    it 'cae a media_url (link) si no hay media_id' do
      result = build(meta_components, header: { media_url: 'https://cdn.example.com/a.jpg' })

      expect(result.components.first[:parameters].first['image']).to eq({ link: 'https://cdn.example.com/a.jpg' })
    end

    it 'falla con mensaje legible si la plantilla exige media y no se envió' do
      result = build(meta_components, {})

      expect(result.success?).to be(false)
      expect(result.error).to include('header image')
    end
  end

  describe 'header LOCATION' do
    let(:meta_components) { [{ 'type' => 'HEADER', 'format' => 'LOCATION' }] }

    it 'arma el parámetro location con lat/long/nombre/dirección' do
      result = build(meta_components,
                     location: { latitude: 37.7749, longitude: -122.4194,
                                 name: 'Sucursal Centro', address: '123 Main St' })

      expect(result.components).to eq(
        [{ type: 'header', parameters: [{ type: 'location', location: {
          latitude: 37.7749, longitude: -122.4194, name: 'Sucursal Centro', address: '123 Main St'
        } }] }]
      )
    end

    it 'falla si faltan las coordenadas' do
      result = build(meta_components, location: { name: 'Sin coords' })

      expect(result.success?).to be(false)
      expect(result.error).to include('LOCATION')
    end
  end

  describe 'botón FLOW' do
    let(:meta_components) do
      [{ 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'FLOW', 'text' => 'Comenzar' }] }]
    end

    it 'emite el componente action con el flow_token recibido' do
      result = build(meta_components, buttons: [{ index: 0, type: 'flow', flow_token: 'tok-123' }])

      expect(result.components).to eq(
        [{ type: 'button', sub_type: 'flow', index: '0',
           parameters: [{ type: 'action', action: { flow_token: 'tok-123', flow_action_data: {} } }] }]
      )
    end

    # Meta exige el componente incluso sin datos iniciales; omitirlo da error #131009.
    it 'genera un flow_token si no se proveyó, en vez de omitir el componente' do
      result = build(meta_components, {})

      component = result.components.first
      expect(component[:sub_type]).to eq('flow')
      expect(component[:parameters].first[:action][:flow_token]).to be_present
    end
  end

  describe 'botón COPY_CODE' do
    let(:meta_components) do
      [{ 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'COPY_CODE', 'text' => 'Copiar' }] }]
    end

    it 'emite coupon_code con el valor enviado' do
      result = build(meta_components, buttons: [{ index: 0, type: 'copy_code', parameter: 'VERANO25' }])

      expect(result.components).to eq(
        [{ type: 'button', sub_type: 'copy_code', index: '0',
           parameters: [{ type: 'coupon_code', coupon_code: 'VERANO25' }] }]
      )
    end

    it 'falla si la plantilla tiene COPY_CODE y no se envió el código' do
      result = build(meta_components, {})

      expect(result.success?).to be(false)
      expect(result.error).to include('COPY_CODE')
    end
  end

  describe 'botones sin parámetro de envío' do
    it 'no emite componente para QUICK_REPLY/PHONE_NUMBER estáticos' do
      meta_components = [{ 'type' => 'BUTTONS', 'buttons' => [
        { 'type' => 'QUICK_REPLY', 'text' => 'Sí' }, { 'type' => 'PHONE_NUMBER', 'text' => 'Llamar' }
      ] }]

      result = build(meta_components, {})

      expect(result.success?).to be(true)
      expect(result.components).to eq([])
    end
  end

  describe 'CAROUSEL' do
    let(:meta_components) do
      [
        { 'type' => 'BODY', 'text' => 'Hola {{1}}' },
        { 'type' => 'CAROUSEL', 'cards' => [
          { 'components' => [
            { 'type' => 'HEADER', 'format' => 'IMAGE' },
            { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'QUICK_REPLY', 'text' => 'Ver más' }] }
          ] },
          { 'components' => [
            { 'type' => 'HEADER', 'format' => 'IMAGE' },
            { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'QUICK_REPLY', 'text' => 'Ver más' }] }
          ] }
        ] }
      ]
    end

    let(:send_params) do
      {
        body_values: { '1' => 'Pablo' },
        cards: [
          { header: { media_id: 'media-0' }, buttons: [{ index: 0, parameter: 'card-0-payload' }] },
          { header: { media_id: 'media-1' }, buttons: [{ index: 0, parameter: 'card-1-payload' }] }
        ]
      }
    end

    it 'arma el componente carousel con card_index 0-based por card' do
      result = build(meta_components, send_params)

      expect(result.success?).to be(true)
      carousel = result.components.find { |c| c[:type] == 'carousel' }
      expect(carousel[:cards].map { |c| c[:card_index] }).to eq([0, 1])
    end

    it 'incluye header y botón dentro de los components de cada card' do
      result = build(meta_components, send_params)

      first_card = result.components.find { |c| c[:type] == 'carousel' }[:cards].first
      expect(first_card[:components]).to eq(
        [
          { type: 'header', parameters: [{ :type => 'image', 'image' => { id: 'media-0' } }] },
          { type: 'button', sub_type: 'quick_reply', index: '0',
            parameters: [{ type: 'payload', payload: 'card-0-payload' }] }
        ]
      )
    end

    it 'mantiene el body de la plantilla junto al carousel' do
      result = build(meta_components, send_params)

      expect(result.components.first).to eq({ type: 'body', parameters: [{ type: 'text', text: 'Pablo' }] })
    end

    it 'falla si no se envían cards' do
      result = build(meta_components, body_values: { '1' => 'Pablo' })

      expect(result.success?).to be(false)
      expect(result.error).to include('cards')
    end

    it 'falla si la cantidad de cards enviadas no coincide con la plantilla' do
      result = build(meta_components, send_params.merge(cards: [send_params[:cards].first]))

      expect(result.success?).to be(false)
      expect(result.error).to include('2 card(s)')
    end
  end

  describe 'AUTHENTICATION / OTP' do
    it 'manda el mismo código en el body y en el botón copy_code' do
      meta_components = [
        { 'type' => 'BODY', 'add_security_recommendation' => true },
        { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'OTP', 'otp_type' => 'COPY_CODE' }] }
      ]

      result = build(meta_components, auth_code: '123456')

      expect(result.components).to eq(
        [
          { type: 'body', parameters: [{ type: 'text', text: '123456' }] },
          { type: 'button', sub_type: 'copy_code', index: '0',
            parameters: [{ type: 'coupon_code', coupon_code: '123456' }] }
        ]
      )
    end

    it 'usa sub_type url para ONE_TAP, con el mismo código en ambos lugares' do
      meta_components = [
        { 'type' => 'BODY' },
        { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'OTP', 'otp_type' => 'ONE_TAP' }] }
      ]

      result = build(meta_components, auth_code: '987654')

      body_value = result.components.first[:parameters].first[:text]
      button = result.components.last
      expect(button[:sub_type]).to eq('url')
      expect(button[:parameters]).to eq([{ type: 'text', text: '987654' }])
      expect(button[:parameters].first[:text]).to eq(body_value)
    end

    it 'falla si no se envía el código' do
      meta_components = [{ 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'OTP', 'otp_type' => 'COPY_CODE' }] }]

      result = build(meta_components, {})

      expect(result.success?).to be(false)
      expect(result.error).to include('auth_code')
    end
  end

  describe 'LIMITED_TIME_OFFER' do
    let(:meta_components) do
      [{ 'type' => 'BODY', 'text' => 'Oferta {{1}}' }, { 'type' => 'LIMITED_TIME_OFFER' }]
    end

    it 'arma el componente con expiration_time_ms' do
      result = build(meta_components, body_values: { '1' => 'Pablo' }, lto_expiration_ms: 1_735_689_600_000)

      lto = result.components.find { |c| c[:type] == 'limited_time_offer' }
      expect(lto).to eq(
        { type: 'limited_time_offer',
          parameters: [{ type: 'limited_time_offer', limited_time_offer: { expiration_time_ms: 1_735_689_600_000 } }] }
      )
    end

    it 'falla si la plantilla declara LTO y no se envió la expiración' do
      result = build(meta_components, body_values: { '1' => 'Pablo' })

      expect(result.success?).to be(false)
      expect(result.error).to include('lto_expiration_ms')
    end
  end

  describe 'tolerancia de entrada' do
    it 'acepta claves symbol y string indistintamente' do
      meta_components = [{ type: 'BODY', text: 'Hola {{1}}' }]

      result = build(meta_components, 'body_values' => { 1 => 'Pablo' })

      expect(result.success?).to be(true)
      expect(result.components.first[:parameters].first[:text]).to eq('Pablo')
    end

    it 'devuelve components vacío (no error) para una plantilla sin nada que parametrizar' do
      result = build([{ 'type' => 'BODY', 'text' => 'Mensaje fijo sin variables' }], {})

      expect(result.success?).to be(true)
      expect(result.components).to eq([])
    end
  end
end
