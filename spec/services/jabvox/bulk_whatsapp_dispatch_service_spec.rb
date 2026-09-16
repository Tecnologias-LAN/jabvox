# frozen_string_literal: true

require 'rails_helper'

# Unit spec for the variable resolution that turns a variable_map + lead fields
# into processed_params (the { "1" => value } the template send forwards to Meta).
RSpec.describe Jabvox::BulkWhatsappDispatchService do
  subject(:service) do
    described_class.new(account: account, inbox: inbox, sender_user: user, actor: user)
  end

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }

  describe '#resolve_params (via send)' do
    let(:fields) do
      { 'nombre' => 'Mel', 'campaign' => 'C12', 'custom:zona' => 'Norte', 'email' => '' }
    end

    def resolve(map)
      service.send(:resolve_params, service.send(:normalize_variable_map, map), fields)
    end

    # resolve_params anida el resultado bajo "body": el canal de WhatsApp solo trata el
    # mensaje como PLANTILLA si processed_params trae las variables ahí (un hash plano
    # se ignoraba y el mensaje salía como texto de sesión — ver el comentario de
    # resolve_params).
    it 'maps {{n}} to the chosen lead field value' do
      expect(resolve('1' => 'nombre', '2' => 'campaign')).to eq('body' => { '1' => 'Mel', '2' => 'C12' })
    end

    it 'resolves a custom field key' do
      expect(resolve('1' => 'custom:zona')).to eq('body' => { '1' => 'Norte' })
    end

    it 'supports a literal "text:" value' do
      expect(resolve('1' => 'text:Hola fijo')).to eq('body' => { '1' => 'Hola fijo' })
    end

    it 'yields empty string for a missing field (never nil)' do
      expect(resolve('1' => 'no_existe')).to eq('body' => { '1' => '' })
    end

    it 'returns {} when the map is blank' do
      expect(resolve({})).to eq({})
    end

    # La clave es el TOKEN de la variable tal cual (no se filtra a solo dígitos): las
    # plantillas NAMED usan {{nombre_variable}}, no un índice numérico, así que forzar
    # dígitos rompía esas plantillas.
    it 'preserves the variable token as-is (supports NAMED templates) and drops blank values' do
      normalized = service.send(:normalize_variable_map, '{{1}}' => 'nombre', '2' => '', '3' => 'email')
      expect(normalized).to eq('{{1}}' => 'nombre', '3' => 'email')
    end
  end

  # El token del envío ya no expira por tiempo (se revoca al terminar el batch). El cleanup
  # de respaldo espera una ventana proporcional al volumen por si el callback final se pierde.
  describe '#backup_cleanup_for (via send)' do
    it 'usa el piso para envíos pequeños' do
      expect(service.send(:backup_cleanup_for, 100)).to eq(described_class::BACKUP_CLEANUP_MIN)
    end

    it 'escala con el número de mensajes por encima del piso' do
      wait = service.send(:backup_cleanup_for, 20_000)
      expect(wait).to be > described_class::BACKUP_CLEANUP_MIN
      expect(wait).to eq(described_class::BACKUP_CLEANUP_PER_MESSAGE * 20_000)
    end

    it 'no supera el techo de seguridad' do
      expect(service.send(:backup_cleanup_for, 10_000_000)).to eq(described_class::BACKUP_CLEANUP_MAX)
    end
  end

  describe '#mint_ephemeral_token (via send)' do
    it 'crea un token SIN expiración por tiempo' do
      token = service.send(:mint_ephemeral_token)
      expect(token.expires_at).to be_nil
      expect(token).not_to be_expired
    end
  end

  # `prepare` (fase 1, en el request) construye el snapshot que se persiste en el
  # batch; `deliver!` (fase 2, en background) reconstruye el service SOLO con ese
  # snapshot, sin los argumentos originales del constructor. Si un dato no viaja
  # en el snapshot, deliver! nunca lo tiene — exactamente lo que le pasaba a
  # cards/auth_code/location/lto_expiration_ms/copy_code (confirmado con un envío
  # real: processed_params llegó a n8n solo con "body", sin "location").
  describe 'los datos de los tipos de plantilla extendidos sobreviven a fase 1 -> fase 2' do
    # Servicio "de fase 2": solo recibe lo que build_payload_snapshot guardó,
    # como hace deliver! de verdad (BulkWhatsappDeliveryJob.perform).
    def service_from_snapshot(snapshot)
      described_class.new(account: account, inbox: inbox, sender_user: user, actor: user)
                     .tap { |s| s.send(:restore_extended_params!, snapshot.with_indifferent_access) }
    end

    it 'la ubicación (header LOCATION) llega intacta a fase 2' do
      original = described_class.new(account: account, inbox: inbox, sender_user: user, actor: user,
                                     location: { latitude: '6.24', longitude: '-75.58', name: 'Sede' })
      snapshot = original.send(:extended_params_snapshot)

      expect(snapshot['location']).to eq('latitude' => '6.24', 'longitude' => '-75.58', 'name' => 'Sede')

      restored = service_from_snapshot(snapshot)
      params = restored.send(:resolve_params, {}, {})
      expect(params['location']).to eq('latitude' => '6.24', 'longitude' => '-75.58', 'name' => 'Sede')
    end

    it 'el código de autenticación llega intacto a fase 2' do
      original = described_class.new(account: account, inbox: inbox, sender_user: user, actor: user,
                                     auth_code: '483920')
      restored = service_from_snapshot(original.send(:extended_params_snapshot))

      expect(restored.send(:resolve_params, {}, {})['auth_code']).to eq('483920')
    end

    it 'las cards del carrusel llegan intactas a fase 2' do
      cards = [{ header: { media_url: 'https://x.com/a.jpg' }, buttons: [{ index: 0, parameter: 'si' }] }]
      original = described_class.new(account: account, inbox: inbox, sender_user: user, actor: user, cards: cards)
      restored = service_from_snapshot(original.send(:extended_params_snapshot))

      expect(restored.send(:resolve_params, {}, {})['cards']).to eq(
        [{ 'header' => { 'media_url' => 'https://x.com/a.jpg' }, 'buttons' => [{ 'index' => 0, 'parameter' => 'si' }] }]
      )
    end

    it 'la oferta por tiempo limitado llega intacta a fase 2' do
      original = described_class.new(account: account, inbox: inbox, sender_user: user, actor: user,
                                     lto_expiration_ms: 1_893_456_000_000)
      restored = service_from_snapshot(original.send(:extended_params_snapshot))

      expect(restored.send(:resolve_params, {}, {})['lto_expiration_ms']).to eq(1_893_456_000_000)
    end

    it 'header_media y flow_button (ya funcionaban) siguen llegando bien' do
      original = described_class.new(account: account, inbox: inbox, sender_user: user, actor: user,
                                     header_media: { media_url: 'https://x.com/h.jpg', media_type: 'image' },
                                     flow_button: { index: 0, flow_id: '999' })
      restored = service_from_snapshot(original.send(:extended_params_snapshot))

      params = restored.send(:resolve_params, {}, {})
      expect(params['header']).to eq('media_url' => 'https://x.com/h.jpg', 'media_type' => 'image')
      expect(params['buttons']).to be_present
    end
  end
end
