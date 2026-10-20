require 'rails_helper'

RSpec.describe Jabvox::WhatsappTemplatesManager do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:manager) { described_class.new(account) }
  let(:base) { 'https://graph.facebook.com/v22.0' }
  # The channel_whatsapp factory's before(:create) hook forces provider_config to
  # 'business_account_id' => '123456789' for whatsapp_cloud (it merges its own
  # defaults IN, overriding whatever we pass) — match that instead of fighting it.
  let(:waba_id) { '123456789' }

  def stub_create_template(response_body = { id: 'tpl-1', status: 'PENDING' })
    stub_request(:post, "#{base}/#{waba_id}/message_templates")
      .to_return(status: 200, body: response_body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe 'FLOW button support in build_buttons_component (new)' do
    it 'sends the exact FLOW button shape Meta expects when creating a template' do
      stub = stub_create_template
      manager.create(inbox, {
                       name: 'plantilla_flow', category: 'MARKETING', language: 'es',
                       body: 'Completa nuestro formulario',
                       buttons: [{ type: 'FLOW', text: 'Comenzar', flow_id: 'meta-flow-42', navigate_screen: 'welcome' }]
                     })

      expect(stub).to have_been_requested
      last_request = WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last
      sent_body = JSON.parse(last_request.body)
      buttons_component = sent_body['components'].find { |c| c['type'] == 'BUTTONS' }
      flow_button = buttons_component['buttons'].find { |b| b['type'] == 'FLOW' }
      expect(flow_button).to include(
        'type' => 'FLOW', 'text' => 'Comenzar', 'flow_id' => 'meta-flow-42',
        'flow_action' => 'NAVIGATE', 'navigate_screen' => 'welcome'
      )
    end

    it 'omits navigate_screen when not provided, but still sets flow_action: NAVIGATE' do
      stub_create_template
      manager.create(inbox, {
                       name: 'plantilla_flow2', category: 'MARKETING', language: 'es', body: 'Hola',
                       buttons: [{ type: 'FLOW', text: 'Ir', flow_id: 'meta-flow-99' }]
                     })

      last_request = WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last
      sent_body = JSON.parse(last_request.body)
      flow_button = sent_body['components'].find { |c| c['type'] == 'BUTTONS' }['buttons'].find { |b| b['type'] == 'FLOW' }
      expect(flow_button['flow_action']).to eq('NAVIGATE')
      expect(flow_button).not_to have_key('navigate_screen')
    end
  end

  describe 'regression: existing template creation still works after the FLOW button change' do
    it 'creates a plain text template with no buttons' do
      stub_create_template
      # Nota: el body ya no puede terminar en variable (regla nueva de validate_body!,
      # que replica el rechazo real de Meta "Leading or Trailing Params Not Allowed").
      result = manager.create(inbox, { name: 'plain_text', category: 'UTILITY', language: 'es', body: 'Hola {{1}}, bienvenido' })
      expect(result[:success]).to be(true)
      expect(result[:template]).to be_persisted
    end

    it 'creates a template with an IMAGE header' do
      stub_create_template
      result = manager.create(inbox, {
                                name: 'with_image', category: 'MARKETING', language: 'es', body: 'Mira esto',
                                header_type: 'IMAGE', header_handle: 'h:abc123'
                              })
      expect(result[:success]).to be(true)
      expect(result[:template].header_type).to eq('IMAGE')
    end

    it 'creates a template with a VIDEO header' do
      stub_create_template
      result = manager.create(inbox, {
                                name: 'with_video', category: 'MARKETING', language: 'es', body: 'Video',
                                header_type: 'VIDEO', header_handle: 'h:vid123'
                              })
      expect(result[:success]).to be(true)
    end

    it 'creates a template with a DOCUMENT header' do
      stub_create_template
      result = manager.create(inbox, {
                                name: 'with_doc', category: 'UTILITY', language: 'es', body: 'Documento adjunto',
                                header_type: 'DOCUMENT', header_handle: 'h:doc123'
                              })
      expect(result[:success]).to be(true)
    end

    it 'still supports a URL button unaffected by the FLOW branch' do
      stub_create_template
      manager.create(inbox, {
                       name: 'with_url_button', category: 'MARKETING', language: 'es', body: 'Visítanos',
                       buttons: [{ type: 'URL', text: 'Ver más', url: 'https://example.com' }]
                     })
      last_request = WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last
      sent_body = JSON.parse(last_request.body)
      btn = sent_body['components'].find { |c| c['type'] == 'BUTTONS' }['buttons'].first
      expect(btn['type']).to eq('URL')
      expect(btn['url']).to eq('https://example.com')
      expect(btn).not_to have_key('flow_id')
    end

    it 'still supports a PHONE_NUMBER button unaffected by the FLOW branch' do
      stub_create_template
      manager.create(inbox, {
                       name: 'with_phone_button', category: 'MARKETING', language: 'es', body: 'Llámanos',
                       buttons: [{ type: 'PHONE_NUMBER', text: 'Llamar', phone_number: '+573001112233' }]
                     })
      last_request = WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last
      sent_body = JSON.parse(last_request.body)
      btn = sent_body['components'].find { |c| c['type'] == 'BUTTONS' }['buttons'].first
      expect(btn['type']).to eq('PHONE_NUMBER')
      expect(btn['phone_number']).to eq('+573001112233')
    end

    it 'updates an existing template body successfully' do
      stub_create_template
      created = manager.create(inbox, { name: 'to_update', category: 'UTILITY', language: 'es', body: 'Original' })[:template]
      stub_request(:post, "#{base}/#{waba_id}/message_templates")
        .to_return(status: 200, body: { success: true }.to_json, headers: { 'Content-Type' => 'application/json' })

      result = manager.update(created, { body: 'Actualizado' })
      expect(result[:success]).to be(true)
      expect(created.reload.body_content).to eq('Actualizado')
    end
  end

  # Meta usa el `example` para revisar la plantilla, así que un "ejemplo"
  # genérico para todas las variables da peores aprobaciones que un valor
  # realista. Contrastado contra una plantilla aprobada real, que lleva
  # "Nombre" como ejemplo de {{nombre}}.
  describe 'ejemplos de las variables del cuerpo' do
    def body_example(params)
      components = manager.send(:build_components, params)
      components.find { |c| c[:type] == 'BODY' }[:example]
    end

    it 'usa el ejemplo que escribió el usuario para cada variable' do
      example = body_example(
        body: 'Hola {{nombre}}, tu pedido {{pedido}} va en camino',
        var_descriptions: { 'nombre' => 'Ana', 'pedido' => 'A-1234' }
      )

      expect(example[:body_text_named_params]).to eq(
        [{ param_name: 'nombre', example: 'Ana' },
         { param_name: 'pedido', example: 'A-1234' }]
      )
    end

    it 'cae al nombre de la variable cuando el usuario no dio ejemplo' do
      example = body_example(body: 'Hola {{nombre_cliente}}, gracias por escribir')

      expect(example[:body_text_named_params]).to eq(
        [{ param_name: 'nombre_cliente', example: 'nombre cliente' }]
      )
    end

    it 'mantiene un ejemplo genérico para variables posicionales sin valor' do
      example = body_example(body: 'Hola {{1}}, gracias por escribir')

      expect(example[:body_text]).to eq([['ejemplo']])
    end

    it 'usa el ejemplo del usuario también en variables posicionales' do
      example = body_example(body: 'Hola {{1}}, gracias', var_descriptions: { '1' => 'Ana' })

      expect(example[:body_text]).to eq([['Ana']])
    end
  end

  describe 'server-side validation (new, sección 3 del diseño de cobertura completa)' do
    describe 'body validation' do
      it 'rejects a body over 1024 characters before calling Meta' do
        result = manager.create(inbox, { name: 'too_long', category: 'UTILITY', language: 'es', body: 'a' * 1025 })
        expect(result[:success]).to be(false)
        expect(result[:error]).to match(/1024/)
        expect(a_request(:post, "#{base}/#{waba_id}/message_templates")).not_to have_been_made
      end

      it 'rejects a body that starts with a variable' do
        result = manager.create(inbox, { name: 'edge_start', category: 'UTILITY', language: 'es', body: '{{1}} bienvenido' })
        expect(result[:success]).to be(false)
        expect(result[:error]).to match(/empezar ni terminar/)
      end

      it 'rejects a body that ends with a variable' do
        result = manager.create(inbox, { name: 'edge_end', category: 'UTILITY', language: 'es', body: 'Hola {{1}}' })
        expect(result[:success]).to be(false)
        expect(result[:error]).to match(/empezar ni terminar/)
      end

      it 'rejects two consecutive variables with no text between them' do
        result = manager.create(inbox, { name: 'consecutive', category: 'UTILITY', language: 'es', body: 'Hola {{1}}{{2}} bienvenido' })
        expect(result[:success]).to be(false)
        expect(result[:error]).to match(/consecutivas/)
      end

      it 'rejects mixing positional and NAMED variables in the same body (bug found in audit)' do
        result = manager.create(inbox, {
                                  name: 'mixed_vars', category: 'UTILITY', language: 'es',
                                  body: 'Hola {{1}}, tu pedido {{numero_pedido}} está listo'
                                })
        expect(result[:success]).to be(false)
        expect(result[:error]).to match(/mezclar/)
      end

      it 'rejects non-sequential positional variables ({{1}} and {{3}} without {{2}})' do
        result = manager.create(inbox, {
                                  name: 'non_sequential', category: 'UTILITY', language: 'es',
                                  body: 'Hola {{1}}, tu código es {{3}}, gracias'
                                })
        expect(result[:success]).to be(false)
        expect(result[:error]).to match(/secuenciales/)
      end

      it 'accepts a well-formed positional body' do
        stub_create_template
        result = manager.create(inbox, {
                                  name: 'ok_positional', category: 'UTILITY', language: 'es',
                                  body: 'Hola {{1}}, tu pedido {{2}} está listo'
                                })
        expect(result[:success]).to be(true)
      end

      it 'accepts a well-formed NAMED body' do
        stub_create_template
        result = manager.create(inbox, {
                                  name: 'ok_named', category: 'UTILITY', language: 'es',
                                  body: 'Hola {{nombre}}, tu pedido {{numero_pedido}} está listo'
                                })
        expect(result[:success]).to be(true)
      end
    end

    describe 'footer validation' do
      it 'rejects a footer over 60 characters' do
        result = manager.create(inbox, {
                                  name: 'long_footer', category: 'UTILITY', language: 'es', body: 'Hola, bienvenido',
                                  footer: 'x' * 61
                                })
        expect(result[:success]).to be(false)
        expect(result[:error]).to match(/60 caracteres/)
      end
    end

    describe 'button validation' do
      def button(type, text: 'Texto', **rest)
        { type: type, text: text }.merge(rest)
      end

      it 'rejects more than 10 combined buttons' do
        buttons = Array.new(11) { |i| button('QUICK_REPLY', text: "Opción #{i}") }
        result = manager.create(inbox, { name: 'too_many_buttons', category: 'UTILITY', language: 'es', body: 'Hola, elige', buttons: buttons })
        expect(result[:success]).to be(false)
        expect(result[:error]).to match(/Máximo 10 botones/)
      end

      it 'rejects COPY_CODE combined with another button type' do
        buttons = [button('COPY_CODE', text: 'PROMO10'), button('QUICK_REPLY', text: 'Ver más')]
        result = manager.create(inbox, { name: 'copy_code_mixed', category: 'UTILITY', language: 'es', body: 'Hola, bienvenido', buttons: buttons })
        expect(result[:success]).to be(false)
        expect(result[:error]).to match(/COPY_CODE no puede combinarse/)
      end

      it 'rejects PHONE_NUMBER and VOICE_CALL together' do
        buttons = [button('PHONE_NUMBER', text: 'Llamar', phone_number: '+573001112233'),
                   button('VOICE_CALL', text: 'Llamar ya', phone_number: '+573001112233')]
        result = manager.create(inbox, { name: 'phone_voice_mixed', category: 'UTILITY', language: 'es', body: 'Hola, bienvenido', buttons: buttons })
        expect(result[:success]).to be(false)
        expect(result[:error]).to match(/mutuamente excluyentes/)
      end

      it 'rejects more than 2 URL buttons' do
        buttons = [button('URL', text: 'Uno', url: 'https://a.com'), button('URL', text: 'Dos', url: 'https://b.com'),
                   button('URL', text: 'Tres', url: 'https://c.com')]
        result = manager.create(inbox, { name: 'too_many_urls', category: 'UTILITY', language: 'es', body: 'Hola, bienvenido', buttons: buttons })
        expect(result[:success]).to be(false)
        expect(result[:error]).to match(/Máximo 2 botón\(es\) de tipo URL/)
      end

      it 'rejects buttons of the same type intercalated with a different type' do
        buttons = [button('QUICK_REPLY', text: 'A'), button('URL', text: 'B', url: 'https://a.com'), button('QUICK_REPLY', text: 'C')]
        result = manager.create(inbox, { name: 'interleaved', category: 'UTILITY', language: 'es', body: 'Hola, bienvenido', buttons: buttons })
        expect(result[:success]).to be(false)
        expect(result[:error]).to match(/agrupados/)
      end

      it 'accepts grouped buttons of different types' do
        stub_create_template
        buttons = [button('QUICK_REPLY', text: 'A'), button('QUICK_REPLY', text: 'B'), button('URL', text: 'C', url: 'https://a.com')]
        result = manager.create(inbox, { name: 'grouped_ok', category: 'UTILITY', language: 'es', body: 'Hola, bienvenido', buttons: buttons })
        expect(result[:success]).to be(true)
      end

      it 'accepts a COPY_CODE button alone' do
        stub_create_template
        result = manager.create(inbox, {
                                  name: 'copy_code_alone', category: 'UTILITY', language: 'es', body: 'Usa este código',
                                  buttons: [button('COPY_CODE', text: 'PROMO10')]
                                })
        expect(result[:success]).to be(true)
        sent_body = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
        btn = sent_body['components'].find { |c| c['type'] == 'BUTTONS' }['buttons'].first
        expect(btn['type']).to eq('COPY_CODE')
      end

      # El front manda COPY_CODE con text vacío (Meta fija el texto) y el código en
      # `example`. El botón debe conservarse y salir con el texto que impone Meta.
      it 'conserva un COPY_CODE sin text y le fija el texto de Meta' do
        stub_create_template
        result = manager.create(inbox, {
                                  name: 'copy_code_sin_text', category: 'UTILITY', language: 'es',
                                  body: 'Usa este código',
                                  buttons: [button('COPY_CODE', text: '', example: 'PROMO10')]
                                })
        expect(result[:success]).to be(true)
        sent_body = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
        btn = sent_body['components'].find { |c| c['type'] == 'BUTTONS' }['buttons'].first
        expect(btn['type']).to eq('COPY_CODE')
        expect(btn['text']).to eq(described_class::COPY_CODE_BUTTON_TEXT)
      end

      it 'accepts a VOICE_CALL button alone' do
        stub_create_template
        result = manager.create(inbox, {
                                  name: 'voice_call_alone', category: 'UTILITY', language: 'es', body: 'Llámanos ya',
                                  buttons: [button('VOICE_CALL', text: 'Llamar', phone_number: '+573001112233')]
                                })
        expect(result[:success]).to be(true)
      end
    end
  end

  describe 'AUTHENTICATION templates (new)' do
    it 'builds BODY/FOOTER/BUTTONS from auth_config instead of free text' do
      stub = stub_create_template
      manager.create(inbox, {
                       name: 'otp_template', category: 'AUTHENTICATION', language: 'es',
                       auth_config: {
                         add_security_recommendation: true, code_expiration_minutes: 10, otp_type: 'COPY_CODE'
                       }
                     })
      expect(stub).to have_been_requested
      sent_body = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
      body_c = sent_body['components'].find { |c| c['type'] == 'BODY' }
      footer_c = sent_body['components'].find { |c| c['type'] == 'FOOTER' }
      otp_btn = sent_body['components'].find { |c| c['type'] == 'BUTTONS' }['buttons'].first
      expect(body_c['add_security_recommendation']).to be(true)
      expect(footer_c['code_expiration_minutes']).to eq(10)
      expect(otp_btn).to include('type' => 'OTP', 'otp_type' => 'COPY_CODE')
    end

    it 'persists the template with template_kind authentication' do
      stub_create_template
      result = manager.create(inbox, {
                                name: 'otp_persist', category: 'AUTHENTICATION', language: 'es',
                                auth_config: { otp_type: 'COPY_CODE' }
                              })
      expect(result[:success]).to be(true)
      expect(result[:template].template_kind).to eq('authentication')
    end

    it 'rejects ONE_TAP/ZERO_TAP without supported_apps' do
      result = manager.create(inbox, {
                                name: 'otp_missing_apps', category: 'AUTHENTICATION', language: 'es',
                                auth_config: { otp_type: 'ONE_TAP' }
                              })
      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/supported_apps/)
    end

    it 'accepts ONE_TAP with supported_apps and includes them in the button' do
      stub_create_template
      result = manager.create(inbox, {
                                name: 'otp_one_tap', category: 'AUTHENTICATION', language: 'es',
                                auth_config: {
                                  otp_type: 'ONE_TAP',
                                  supported_apps: [{ package_name: 'com.jabvox.app', signature_hash: 'ABC123' }]
                                }
                              })
      expect(result[:success]).to be(true)
      sent_body = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
      otp_btn = sent_body['components'].find { |c| c['type'] == 'BUTTONS' }['buttons'].first
      expect(otp_btn['supported_apps']).to eq([{ 'package_name' => 'com.jabvox.app', 'signature_hash' => 'ABC123' }])
    end

    it 'rejects code_expiration_minutes outside 1-90' do
      result = manager.create(inbox, {
                                name: 'otp_bad_expiration', category: 'AUTHENTICATION', language: 'es',
                                auth_config: { otp_type: 'COPY_CODE', code_expiration_minutes: 200 }
                              })
      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/code_expiration_minutes/)
    end
  end

  describe 'CAROUSEL templates (new)' do
    def carousel_card(header_type: 'IMAGE', handle: 'h:card1', body: nil, buttons: [])
      { header_type: header_type, header_handle: handle, body_content: body, buttons: buttons }
    end

    it 'builds a CAROUSEL component with 2 cards' do
      stub = stub_create_template
      manager.create(inbox, {
                       name: 'carousel_tpl', category: 'MARKETING', language: 'es', template_kind: 'carousel',
                       body: 'Mira nuestros productos',
                       cards: [carousel_card, carousel_card(handle: 'h:card2')]
                     })
      expect(stub).to have_been_requested
      sent_body = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
      carousel_c = sent_body['components'].find { |c| c['type'] == 'CAROUSEL' }
      expect(carousel_c['cards'].length).to eq(2)
      expect(carousel_c['cards'].first['components'].first).to include('type' => 'HEADER', 'format' => 'IMAGE')
    end

    it 'rejects carousel with fewer than 2 cards' do
      result = manager.create(inbox, {
                                name: 'carousel_too_few', category: 'MARKETING', language: 'es', template_kind: 'carousel',
                                body: 'Mira nuestros productos', cards: [carousel_card]
                              })
      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/entre 2 y 10/)
    end

    it 'rejects a FLOW button inside a card' do
      result = manager.create(inbox, {
                                name: 'carousel_flow_button', category: 'MARKETING', language: 'es', template_kind: 'carousel',
                                body: 'Mira nuestros productos',
                                cards: [
                                  carousel_card(buttons: [{ type: 'FLOW', text: 'Ir', flow_id: 'x' }]),
                                  carousel_card(handle: 'h:card2')
                                ]
                              })
      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/no está permitido dentro de una card/)
    end

    it 'rejects cards with inconsistent button type sets' do
      result = manager.create(inbox, {
                                name: 'carousel_inconsistent', category: 'MARKETING', language: 'es', template_kind: 'carousel',
                                body: 'Mira nuestros productos',
                                cards: [
                                  carousel_card(buttons: [{ type: 'QUICK_REPLY', text: 'A' }]),
                                  carousel_card(handle: 'h:card2', buttons: [{ type: 'URL', text: 'B', url: 'https://a.com' }])
                                ]
                              })
      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/mismo conjunto y orden/)
    end

    it 'persists template_kind carousel and cards_json' do
      stub_create_template
      result = manager.create(inbox, {
                                name: 'carousel_persist', category: 'MARKETING', language: 'es', template_kind: 'carousel',
                                body: 'Mira nuestros productos',
                                cards: [carousel_card, carousel_card(handle: 'h:card2')]
                              })
      expect(result[:success]).to be(true)
      expect(result[:template].template_kind).to eq('carousel')
      expect(result[:template].cards_json.length).to eq(2)
    end
  end

  describe 'LOCATION header (new)' do
    it 'builds a HEADER component with format LOCATION and no example' do
      stub = stub_create_template
      manager.create(inbox, {
                       name: 'location_tpl', category: 'UTILITY', language: 'es',
                       header_type: 'LOCATION', body: 'Aquí está nuestra ubicación'
                     })
      expect(stub).to have_been_requested
      sent_body = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
      header_c = sent_body['components'].find { |c| c['type'] == 'HEADER' }
      expect(header_c).to eq('type' => 'HEADER', 'format' => 'LOCATION')
    end

    it 'persists location_header: true' do
      stub_create_template
      result = manager.create(inbox, {
                                name: 'location_persist', category: 'UTILITY', language: 'es',
                                header_type: 'LOCATION', body: 'Aquí está nuestra ubicación'
                              })
      expect(result[:success]).to be(true)
      expect(result[:template].location_header).to be(true)
    end
  end

  describe 'LIMITED_TIME_OFFER (new)' do
    it 'adds the LIMITED_TIME_OFFER component when limited_time_offer is true and category is MARKETING' do
      stub = stub_create_template
      manager.create(inbox, {
                       name: 'lto_tpl', category: 'MARKETING', language: 'es',
                       body: 'Oferta especial por tiempo limitado', limited_time_offer: true
                     })
      expect(stub).to have_been_requested
      sent_body = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
      lto_c = sent_body['components'].find { |c| c['type'] == 'LIMITED_TIME_OFFER' }
      # Meta exige `text` dentro del componente; sin él responde
      # "(#100) The parameter ...['limited_time_offer']['text'] is required".
      expect(lto_c).to eq(
        'type' => 'LIMITED_TIME_OFFER',
        'limited_time_offer' => { 'text' => 'Oferta por tiempo limitado', 'has_expiration' => true }
      )
    end

    it 'does not add LIMITED_TIME_OFFER when category is not MARKETING' do
      stub = stub_create_template
      manager.create(inbox, {
                       name: 'lto_wrong_category', category: 'UTILITY', language: 'es',
                       body: 'Oferta especial por tiempo limitado', limited_time_offer: true
                     })
      expect(stub).to have_been_requested
      sent_body = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
      expect(sent_body['components'].find { |c| c['type'] == 'LIMITED_TIME_OFFER' }).to be_nil
    end

    it 'persists limited_time_offer: true' do
      stub_create_template
      result = manager.create(inbox, {
                                name: 'lto_persist', category: 'MARKETING', language: 'es',
                                body: 'Oferta especial por tiempo limitado', limited_time_offer: true
                              })
      expect(result[:success]).to be(true)
      expect(result[:template].limited_time_offer).to be(true)
    end
  end

  describe 'upsert_from_meta reading back new template kinds (sync, must never raise)' do
    it 'imports an AUTHENTICATION template from Meta without exploding' do
      raw = {
        'id' => 'meta-auth-1', 'name' => 'auth_from_meta', 'language' => 'es', 'category' => 'AUTHENTICATION',
        'status' => 'APPROVED',
        'components' => [
          { 'type' => 'BODY', 'add_security_recommendation' => true },
          { 'type' => 'FOOTER', 'code_expiration_minutes' => 5 },
          { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'OTP', 'otp_type' => 'COPY_CODE' }] }
        ]
      }
      expect { manager.send(:upsert_from_meta, raw, inbox) }.not_to raise_error
      tpl = account.jabvox_whatsapp_templates.find_by(name: 'auth_from_meta')
      expect(tpl.template_kind).to eq('authentication')
      expect(tpl.auth_config_json['code_expiration_minutes']).to eq(5)
    end

    it 'imports a CAROUSEL template from Meta without exploding' do
      raw = {
        'id' => 'meta-carousel-1', 'name' => 'carousel_from_meta', 'language' => 'es', 'category' => 'MARKETING',
        'status' => 'APPROVED',
        'components' => [
          { 'type' => 'BODY', 'text' => 'Mira nuestros productos' },
          { 'type' => 'CAROUSEL', 'cards' => [{ 'components' => [{ 'type' => 'HEADER', 'format' => 'IMAGE' }] }] }
        ]
      }
      expect { manager.send(:upsert_from_meta, raw, inbox) }.not_to raise_error
      tpl = account.jabvox_whatsapp_templates.find_by(name: 'carousel_from_meta')
      expect(tpl.template_kind).to eq('carousel')
      expect(tpl.cards_json.length).to eq(1)
    end

    it 'imports a LOCATION header template from Meta without exploding' do
      raw = {
        'id' => 'meta-loc-1', 'name' => 'location_from_meta', 'language' => 'es', 'category' => 'UTILITY',
        'status' => 'APPROVED',
        'components' => [
          { 'type' => 'HEADER', 'format' => 'LOCATION' },
          { 'type' => 'BODY', 'text' => 'Aquí está nuestra ubicación' }
        ]
      }
      expect { manager.send(:upsert_from_meta, raw, inbox) }.not_to raise_error
      tpl = account.jabvox_whatsapp_templates.find_by(name: 'location_from_meta')
      expect(tpl.location_header).to be(true)
    end

    it 'imports a LIMITED_TIME_OFFER template from Meta without exploding' do
      raw = {
        'id' => 'meta-lto-1', 'name' => 'lto_from_meta', 'language' => 'es', 'category' => 'MARKETING',
        'status' => 'APPROVED',
        'components' => [
          { 'type' => 'BODY', 'text' => 'Oferta especial' },
          { 'type' => 'LIMITED_TIME_OFFER', 'limited_time_offer' => { 'has_expiration' => true } }
        ]
      }
      expect { manager.send(:upsert_from_meta, raw, inbox) }.not_to raise_error
      tpl = account.jabvox_whatsapp_templates.find_by(name: 'lto_from_meta')
      expect(tpl.limited_time_offer).to be(true)
    end
  end
  # ─────────────────────────────────────────────────────────────────────
  # PRUEBAS DE ESTRÉS: revalidación de longitudes en backend (doble candado).
  # El frontend ya valida en vivo, pero estos casos simulan un POST directo a
  # la API saltándose el cliente. Cada tope se prueba en el borde exacto (pasa)
  # y un carácter por encima (falla). El conteo es por grafemas: un emoji
  # compuesto cuenta como 1, igual que Intl.Segmenter en el front.
  # ─────────────────────────────────────────────────────────────────────
  describe 'stress: backend button length revalidation (new, doble candado)' do
    def button(type, text: 'Texto', **rest)
      { type: type, text: text }.merge(rest)
    end

    it 'acepta un texto de botón de exactamente 25 caracteres' do
      stub_create_template
      result = manager.create(inbox, {
                                name: 'btn_text_limit_ok', category: 'UTILITY', language: 'es',
                                body: 'Hola, bienvenido', buttons: [button('QUICK_REPLY', text: 'A' * 25)]
                              })
      expect(result[:success]).to be(true)
    end

    it 'rechaza un texto de botón de 26 caracteres' do
      result = manager.create(inbox, {
                                name: 'btn_text_over', category: 'UTILITY', language: 'es',
                                body: 'Hola, bienvenido', buttons: [button('QUICK_REPLY', text: 'A' * 26)]
                              })
      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/Botón 1: el texto no puede superar 25/)
    end

    it 'cuenta por grafemas: 25 emojis compuestos pasan aunque sean miles de code points' do
      stub_create_template
      family = "\u{1F468}‍\u{1F469}‍\u{1F467}" # 👨‍👩‍👧 = 1 grafema, 8 UTF-16
      result = manager.create(inbox, {
                                name: 'btn_emoji_ok', category: 'UTILITY', language: 'es',
                                body: 'Hola, bienvenido', buttons: [button('QUICK_REPLY', text: family * 25)]
                              })
      expect(result[:success]).to be(true)
    end

    it 'rechaza 26 emojis compuestos en el texto de un botón' do
      family = "\u{1F468}‍\u{1F469}‍\u{1F467}"
      result = manager.create(inbox, {
                                name: 'btn_emoji_over', category: 'UTILITY', language: 'es',
                                body: 'Hola, bienvenido', buttons: [button('QUICK_REPLY', text: family * 26)]
                              })
      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/Botón 1: el texto no puede superar 25/)
    end

    it 'rechaza una URL de más de 2000 caracteres' do
      long = "https://a.com/#{'x' * 2000}"
      result = manager.create(inbox, {
                                name: 'btn_url_over', category: 'UTILITY', language: 'es',
                                body: 'Hola, bienvenido', buttons: [button('URL', text: 'Ir', url: long)]
                              })
      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/Botón 1: la URL no puede superar 2000/)
    end

    it 'rechaza un número de teléfono de más de 20 caracteres' do
      result = manager.create(inbox, {
                                name: 'btn_phone_over', category: 'UTILITY', language: 'es',
                                body: 'Hola, bienvenido',
                                buttons: [button('PHONE_NUMBER', text: 'Llamar', phone_number: '+' + ('1' * 21))]
                              })
      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/Botón 1: el número no puede superar 20/)
    end

    it 'rechaza un código COPY_CODE de más de 20 caracteres' do
      result = manager.create(inbox, {
                                name: 'btn_code_over', category: 'UTILITY', language: 'es',
                                body: 'Usa este código', buttons: [button('COPY_CODE', text: '', example: 'Z' * 21)]
                              })
      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/Botón 1: el código no puede superar 20/)
    end

    it 'NO cuenta el texto de un COPY_CODE para el tope de 25 (Meta lo fija)' do
      stub_create_template
      # Aunque el text crudo sea larguísimo, COPY_CODE se exceptúa del tope de
      # texto porque el backend lo reemplaza por el texto fijo de Meta.
      result = manager.create(inbox, {
                                name: 'btn_code_text_ignored', category: 'UTILITY', language: 'es',
                                body: 'Usa este código', buttons: [button('COPY_CODE', text: 'X' * 99, example: 'PROMO10')]
                              })
      expect(result[:success]).to be(true)
    end
  end

  describe 'stress: carousel card button length revalidation (new)' do
    def carousel_card(header_type: 'IMAGE', handle: 'h:card1', body: nil, buttons: [])
      { header_type: header_type, header_handle: handle, body_content: body, buttons: buttons }
    end

    it 'rechaza una URL demasiado larga dentro de un botón de card' do
      long = "https://a.com/#{'x' * 2000}"
      result = manager.create(inbox, {
                                name: 'carousel_url_over', category: 'MARKETING', language: 'es', template_kind: 'carousel',
                                body: 'Mira nuestros productos',
                                cards: [
                                  carousel_card(buttons: [{ type: 'URL', text: 'Ir', url: long }]),
                                  carousel_card(handle: 'h:card2', buttons: [{ type: 'URL', text: 'Ir', url: 'https://b.com' }])
                                ]
                              })
      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/Card 1, botón 1: la URL no puede superar 2000/)
    end

    it 'rechaza un texto de botón de card de más de 25 caracteres' do
      result = manager.create(inbox, {
                                name: 'carousel_text_over', category: 'MARKETING', language: 'es', template_kind: 'carousel',
                                body: 'Mira nuestros productos',
                                cards: [
                                  carousel_card(buttons: [{ type: 'QUICK_REPLY', text: 'A' * 26 }]),
                                  carousel_card(handle: 'h:card2', buttons: [{ type: 'QUICK_REPLY', text: 'B' }])
                                ]
                              })
      expect(result[:success]).to be(false)
      expect(result[:error]).to match(/Card 1, botón 1: el texto no puede superar 25/)
    end

    it 'acepta cards con botones dentro de los topes' do
      stub_create_template
      result = manager.create(inbox, {
                                name: 'carousel_len_ok', category: 'MARKETING', language: 'es', template_kind: 'carousel',
                                body: 'Mira nuestros productos',
                                cards: [
                                  carousel_card(buttons: [{ type: 'QUICK_REPLY', text: 'Ver' }]),
                                  carousel_card(handle: 'h:card2', buttons: [{ type: 'QUICK_REPLY', text: 'Comprar' }])
                                ]
                              })
      expect(result[:success]).to be(true)
    end
  end

  describe 'stress: lto_text personalizado (new)' do
    it 'usa el lto_text que manda el usuario en lugar del texto por defecto' do
      stub = stub_create_template
      manager.create(inbox, {
                       name: 'lto_custom_text', category: 'MARKETING', language: 'es',
                       body: 'Oferta especial', limited_time_offer: true, lto_text: '¡Solo hoy! 🔥'
                     })
      expect(stub).to have_been_requested
      sent_body = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
      lto_c = sent_body['components'].find { |c| c['type'] == 'LIMITED_TIME_OFFER' }
      expect(lto_c['limited_time_offer']['text']).to eq('¡Solo hoy! 🔥')
    end

    it 'cae al texto por defecto cuando lto_text viene en blanco' do
      stub = stub_create_template
      manager.create(inbox, {
                       name: 'lto_blank_text', category: 'MARKETING', language: 'es',
                       body: 'Oferta especial', limited_time_offer: true, lto_text: '   '
                     })
      expect(stub).to have_been_requested
      sent_body = JSON.parse(WebMock::RequestRegistry.instance.requested_signatures.hash.keys.last.body)
      lto_c = sent_body['components'].find { |c| c['type'] == 'LIMITED_TIME_OFFER' }
      expect(lto_c['limited_time_offer']['text']).to eq('Oferta por tiempo limitado')
    end
  end
end
