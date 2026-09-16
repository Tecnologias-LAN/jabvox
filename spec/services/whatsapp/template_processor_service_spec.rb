require 'rails_helper'

describe Whatsapp::TemplateProcessorService do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_whatsapp, account: account, validate_provider_config: false, sync_templates: false) }

  def build_service(template_params)
    described_class.new(channel: channel, template_params: template_params, message: nil)
  end

  before do
    channel.update_column(:message_templates, [template]) # rubocop:disable Rails/SkipsModelValidations -- solo setup del fixture, sin nada que validar
  end

  describe 'body parameters' do
    context 'when the template uses POSITIONAL variables' do
      let(:template) do
        {
          'name' => 'positional_template', 'language' => 'es', 'status' => 'approved',
          'parameter_format' => 'POSITIONAL',
          'components' => [{ 'type' => 'BODY', 'text' => 'Hola {{1}}, tu pedido {{2}} llegó' }]
        }
      end

      it 'sends positional params as a bare array, in numeric order regardless of hash insertion order' do
        # Hash arrives with "2" inserted before "1" — Ruby Hash preserves insertion
        # order, not numeric order, so this reproduces a real out-of-order payload.
        params = build_service(
          'name' => 'positional_template', 'language' => 'es',
          'processed_params' => { 'body' => { '2' => 'ABC123', '1' => 'Mel' } }
        ).call

        components = params[3]
        body = components.find { |c| c[:type] == 'body' }
        expect(body[:parameters]).to eq(
          [{ type: 'text', text: 'Mel' }, { type: 'text', text: 'ABC123' }]
        )
      end
    end

    context 'when the template uses NAMED variables' do
      let(:template) do
        {
          'name' => 'named_template', 'language' => 'es', 'status' => 'approved',
          'components' => [{
            'type' => 'BODY', 'text' => 'Hola {{nombre}}, queremos que nos cuentes más',
            'example' => { 'body_text_named_params' => [{ 'param_name' => 'nombre', 'example' => 'Mel' }] }
          }]
        }
      end

      it 'sends each param with its parameter_name, inferred from the body text' do
        params = build_service(
          'name' => 'named_template', 'language' => 'es',
          'processed_params' => { 'body' => { 'nombre' => 'Estrada' } }
        ).call

        components = params[3]
        body = components.find { |c| c[:type] == 'body' }
        expect(body[:parameters]).to eq(
          [{ type: 'text', parameter_name: 'nombre', text: 'Estrada' }]
        )
      end
    end
  end

  describe 'header parameters' do
    %w[IMAGE VIDEO DOCUMENT].each do |format|
      context "when the header format is #{format}" do
        let(:template) do
          {
            'name' => 'media_template', 'language' => 'es', 'status' => 'approved',
            'components' => [
              { 'type' => 'HEADER', 'format' => format, 'example' => { 'header_handle' => ['https://scontent.whatsapp.net/example'] } },
              { 'type' => 'BODY', 'text' => 'Hola' }
            ]
          }
        end

        it "builds a #{format.downcase} header parameter from the media sent by the caller" do
          resolver = instance_double(Whatsapp::TemplateMediaResolverService, call: nil)
          allow(Whatsapp::TemplateMediaResolverService).to receive(:new).and_return(resolver)

          params = build_service(
            'name' => 'media_template', 'language' => 'es',
            'processed_params' => { 'header' => { 'media_url' => 'https://cdn.example.com/file', 'media_type' => format.downcase } }
          ).call

          components = params[3]
          header = components.find { |c| c[:type] == 'header' }
          expect(header[:parameters].first[:type]).to eq(format.downcase)
        end
      end
    end

    context 'when no header is sent but the template has an approved media example' do
      let(:template) do
        {
          'name' => 'media_template', 'language' => 'es', 'status' => 'approved',
          'components' => [
            { 'type' => 'HEADER', 'format' => 'IMAGE', 'example' => { 'header_handle' => ['https://scontent.whatsapp.net/example'] } },
            { 'type' => 'BODY', 'text' => 'Hola' }
          ]
        }
      end

      it 'falls back to the template approved example so Meta does not reject a missing header' do
        resolver = instance_double(Whatsapp::TemplateMediaResolverService, call: nil)
        allow(Whatsapp::TemplateMediaResolverService).to receive(:new).and_return(resolver)

        params = build_service(
          'name' => 'media_template', 'language' => 'es', 'processed_params' => {}
        ).call

        components = params[3]
        header = components.find { |c| c[:type] == 'header' }
        expect(header).to be_present
      end
    end
  end

  describe 'button parameters' do
    context 'when the template has a FLOW button' do
      let(:template) do
        {
          'name' => 'flow_template', 'language' => 'es_CO', 'status' => 'approved',
          'components' => [
            { 'type' => 'BODY', 'text' => 'Hola {{nombre}}' },
            { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'FLOW', 'text' => 'Empezar', 'flow_id' => '123' }] }
          ]
        }
      end

      it 'always emits the button/flow component, even with no agent-supplied parameter' do
        params = build_service(
          'name' => 'flow_template', 'language' => 'es_CO',
          'processed_params' => { 'body' => { 'nombre' => 'Estrada' }, 'buttons' => [{ 'type' => 'flow' }] }
        ).call

        components = params[3]
        button = components.find { |c| c[:type] == 'button' }
        expect(button).to include(sub_type: 'flow', index: 0)
        expect(button[:parameters].first[:type]).to eq('action')
        expect(button[:parameters].first[:action][:flow_token]).to be_present
      end

      it 'reproduces the exact production failure when the button is omitted (regression guard)' do
        # This is the shape processed_params had in production before the fix
        # (no buttons key at all) — it must NOT emit any button component, which
        # is exactly what caused Meta's "#131009 Components sub_type invalid".
        # The fix is on the CALLER (frontend / n8n) always including the flow
        # button; here we just confirm the processor emits nothing extra when
        # it's missing, rather than silently guessing one.
        params = build_service(
          'name' => 'flow_template', 'language' => 'es_CO',
          'processed_params' => { 'body' => { 'nombre' => 'Estrada' } }
        ).call

        components = params[3]
        expect(components.find { |c| c[:type] == 'button' }).to be_nil
      end
    end

    context 'when the template has a static QUICK_REPLY button' do
      let(:template) do
        {
          'name' => 'quick_reply_template', 'language' => 'es', 'status' => 'approved',
          'components' => [
            { 'type' => 'BODY', 'text' => 'Hola' },
            { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'QUICK_REPLY', 'text' => 'Sí' }] }
          ]
        }
      end

      it 'does not emit a button component (Meta rejects one for a static quick reply)' do
        params = build_service(
          'name' => 'quick_reply_template', 'language' => 'es',
          'processed_params' => { 'buttons' => [{ 'type' => 'quick_reply' }] }
        ).call

        components = params[3]
        expect(components.find { |c| c[:type] == 'button' }).to be_nil
      end
    end

    context 'when the template has a dynamic URL button' do
      let(:template) do
        {
          'name' => 'url_template', 'language' => 'es', 'status' => 'approved',
          'components' => [
            { 'type' => 'BODY', 'text' => 'Hola' },
            { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'URL', 'text' => 'Ver', 'url' => 'https://example.com/{{1}}' }] }
          ]
        }
      end

      it 'emits a button/url component with the dynamic suffix' do
        params = build_service(
          'name' => 'url_template', 'language' => 'es',
          'processed_params' => { 'buttons' => [{ 'type' => 'url', 'parameter' => 'abc123' }] }
        ).call

        components = params[3]
        button = components.find { |c| c[:type] == 'button' }
        expect(button).to include(sub_type: 'url', index: 0)
        expect(button[:parameters]).to eq([{ type: 'text', text: 'abc123' }])
      end

      it 'does not emit a component when the URL button has no dynamic suffix yet' do
        params = build_service(
          'name' => 'url_template', 'language' => 'es',
          'processed_params' => { 'buttons' => [{ 'type' => 'url', 'parameter' => '' }] }
        ).call

        components = params[3]
        expect(components.find { |c| c[:type] == 'button' }).to be_nil
      end
    end

    context 'when the template has a COPY_CODE button' do
      let(:template) do
        {
          'name' => 'coupon_template', 'language' => 'es', 'status' => 'approved',
          'components' => [
            { 'type' => 'BODY', 'text' => 'Hola' },
            { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'COPY_CODE', 'text' => 'Copiar código' }] }
          ]
        }
      end

      it 'emits a button/copy_code component' do
        params = build_service(
          'name' => 'coupon_template', 'language' => 'es',
          'processed_params' => { 'buttons' => [{ 'type' => 'copy_code', 'parameter' => 'SAVE10' }] }
        ).call

        components = params[3]
        button = components.find { |c| c[:type] == 'button' }
        expect(button).to include(sub_type: 'copy_code', index: 0)
        expect(button[:parameters]).to eq([{ type: 'coupon_code', coupon_code: 'SAVE10' }])
      end
    end
  end

  describe 'footer parameters' do
    let(:template) do
      {
        'name' => 'footer_template', 'language' => 'es', 'status' => 'approved',
        'components' => [
          { 'type' => 'BODY', 'text' => 'Hola' },
          { 'type' => 'FOOTER', 'text' => 'Pie {{1}}' }
        ]
      }
    end

    it 'emits a footer component when a value is present' do
      params = build_service(
        'name' => 'footer_template', 'language' => 'es',
        'processed_params' => { 'footer' => { '1' => 'Empresa' } }
      ).call

      components = params[3]
      footer = components.find { |c| c[:type] == 'footer' }
      expect(footer[:parameters]).to eq([{ type: 'text', text: 'Empresa' }])
    end
  end

  describe 'unknown/unapproved template' do
    let(:template) { { 'name' => 'other_template', 'language' => 'es', 'status' => 'approved', 'components' => [] } }

    it 'returns nil processed params instead of raising' do
      params = build_service(
        'name' => 'does_not_exist', 'language' => 'es', 'processed_params' => { 'body' => { '1' => 'x' } }
      ).call

      expect(params[3]).to be_nil
    end
  end
end
