require 'rails_helper'

RSpec.describe JabvoxWhatsappTemplate do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { create(:inbox, account: account, channel: channel) }

  def build_template(attrs = {})
    account.jabvox_whatsapp_templates.new(
      {
        inbox: inbox, name: 'plantilla_test', language: 'es', category: 'UTILITY',
        body_content: 'Hola, bienvenido'
      }.merge(attrs)
    )
  end

  describe 'new columns (sección 2 del diseño de cobertura completa)' do
    it 'defaults template_kind to standard' do
      expect(build_template.template_kind).to eq('standard')
    end

    it 'defaults cards_json to an empty array' do
      expect(build_template.cards_json).to eq([])
    end

    it 'defaults auth_config_json to an empty hash' do
      expect(build_template.auth_config_json).to eq({})
    end

    it 'defaults location_header to false' do
      expect(build_template.location_header).to be(false)
    end

    it 'defaults limited_time_offer to false' do
      expect(build_template.limited_time_offer).to be(false)
    end

    it 'persists all new columns' do
      tpl = build_template(
        template_kind: 'carousel',
        cards_json: [{ 'header_type' => 'IMAGE' }],
        auth_config_json: { 'otp_type' => 'COPY_CODE' },
        location_header: true,
        limited_time_offer: true
      )
      tpl.save!
      tpl.reload
      expect(tpl.template_kind).to eq('carousel')
      expect(tpl.cards_json).to eq([{ 'header_type' => 'IMAGE' }])
      expect(tpl.auth_config_json).to eq({ 'otp_type' => 'COPY_CODE' })
      expect(tpl.location_header).to be(true)
      expect(tpl.limited_time_offer).to be(true)
    end
  end

  describe 'constants' do
    it 'HEADER_TYPES includes LOCATION' do
      expect(described_class::HEADER_TYPES).to include('LOCATION')
    end

    it 'TEMPLATE_KINDS has the four supported kinds' do
      expect(described_class::TEMPLATE_KINDS).to contain_exactly('standard', 'authentication', 'carousel', 'flow')
    end
  end

  describe 'validations' do
    it 'rejects an unknown template_kind' do
      tpl = build_template(template_kind: 'bogus')
      expect(tpl).not_to be_valid
      expect(tpl.errors[:template_kind]).to be_present
    end

    it 'accepts each of the supported template_kind values' do
      described_class::TEMPLATE_KINDS.each do |kind|
        tpl = build_template(template_kind: kind)
        tpl.valid?
        expect(tpl.errors[:template_kind]).to be_empty
      end
    end
  end

  describe 'scopes' do
    it 'by_kind filters by template_kind' do
      standard = build_template(name: 'standard_tpl')
      standard.save!
      carousel = build_template(name: 'carousel_tpl', template_kind: 'carousel', body_content: nil,
                                cards_json: [{ 'header_type' => 'IMAGE' }, { 'header_type' => 'IMAGE' }])
      carousel.save!

      expect(account.jabvox_whatsapp_templates.by_kind('carousel')).to contain_exactly(carousel)
      expect(account.jabvox_whatsapp_templates.by_kind(nil)).to contain_exactly(standard, carousel)
    end
  end

  describe 'snapshot_payload' do
    it 'includes the new fields for version history' do
      tpl = build_template(template_kind: 'authentication', auth_config_json: { 'otp_type' => 'COPY_CODE' })
      payload = tpl.snapshot_payload
      expect(payload[:template_kind]).to eq('authentication')
      expect(payload[:auth_config_json]).to eq({ 'otp_type' => 'COPY_CODE' })
      expect(payload).to have_key(:cards_json)
      expect(payload).to have_key(:location_header)
      expect(payload).to have_key(:limited_time_offer)
    end
  end
end
