# frozen_string_literal: true

require 'rails_helper'

# El prefijo internacional debe sobrevivir desde que el contacto se guarda hasta
# cada canal de salida: WhatsApp, SMS, llamadas VoIP y el marcador.
#
# La regla es siempre la misma: el teléfono se guarda en E.164 ("+573001234567")
# y cada canal lo usa quitando SOLO el "+", nunca el código de país.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'El prefijo se conserva en todos los canales de salida' do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, phone_number: '+573001234567') }

  describe 'lo que se guarda' do
    it 'el contacto queda con el prefijo en el teléfono' do
      expect(contact.phone_number).to eq('+573001234567')
    end

    it 'y con las piezas separadas para las pantallas' do
      expect(contact.phone_country_code_jabvox).to eq('+57')
      expect(contact.phone_national_jabvox).to eq('3001234567')
    end
  end

  describe 'llamadas (VoIP, click-to-call y marcador)' do
    it 'marca con el código de país, solo sin el "+"' do
      dialed = Jabvox::PhoneNormalizer.for_dialing(contact.phone_number)

      expect(dialed).to eq('573001234567')
      expect(dialed).to start_with('57')
    end

    it 'el resolutor del marcador usa el teléfono del contacto con su prefijo' do
      lead = JabvoxLead.create!(account: account, contact: contact)

      number = Jabvox::DialNumberResolver.resolve(lead: lead, field: 'phone')

      expect(number).to eq('573001234567')
    end

    it 'un campo personalizado sin prefijo lo recibe del país configurado' do
      lead = JabvoxLead.create!(account: account, contact: contact,
                                custom_fields_jabvox: { 'movil_2_c' => '3009999999' })

      number = Jabvox::DialNumberResolver.resolve(lead: lead, field: 'movil_2_c', prefix: '57')

      expect(number).to eq('573009999999')
    end

    it 'no duplica el prefijo en un campo personalizado que ya lo trae' do
      lead = JabvoxLead.create!(account: account, contact: contact,
                                custom_fields_jabvox: { 'movil_2_c' => '573009999999' })

      number = Jabvox::DialNumberResolver.resolve(lead: lead, field: 'movil_2_c', prefix: '57')

      expect(number).to eq('573009999999')
    end
  end

  describe 'SMS' do
    it 'envía con el código de país, solo sin el "+"' do
      # El servicio de SMS sanea igual que el marcador: quita "+" y separadores.
      sanitized = contact.phone_number.gsub(/[+\s\-()]/, '')

      expect(sanitized).to eq('573001234567')
    end
  end

  describe 'WhatsApp masivo desde un CSV' do
    def normalized(raw, country)
      described = Jabvox::LeadIdentityService.normalize_phone(raw, country).value
      described&.delete_prefix('+')
    end

    it 'agrega el prefijo del país a un número local del archivo' do
      expect(normalized('3001234567', 'CO')).to eq('573001234567')
    end

    it 'no duplica el prefijo cuando el archivo ya lo trae' do
      expect(normalized('+573001234567', 'CO')).to eq('573001234567')
      expect(normalized('573001234567', 'CO')).to eq('573001234567')
    end

    it 'usa el país elegido, no el que sugiere el número' do
      expect(normalized('3001234567', 'AF')).to eq('933001234567')
    end
  end

  describe 'números que no son de Colombia' do
    it 'conserva prefijos largos al marcar' do
      samoa = create(:contact, account: account, phone_number: '+16847331234')

      expect(Jabvox::PhoneNormalizer.for_dialing(samoa.phone_number)).to eq('16847331234')
      expect(samoa.phone_country_code_jabvox).to eq('+1684')
    end
  end
end
# rubocop:enable RSpec/DescribeClass
