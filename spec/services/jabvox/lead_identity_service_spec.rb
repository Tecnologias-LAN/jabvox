# frozen_string_literal: true

require 'rails_helper'

describe Jabvox::LeadIdentityService do
  describe '.normalize_phone' do
    it 'antepone el prefijo del país a un número local' do
      result = described_class.normalize_phone('3001234567', 'CO')

      expect(result.value).to eq('+573001234567')
      expect(result.status).to eq(:ok)
    end

    it 'respeta un número que ya trae el prefijo con + y lo marca' do
      result = described_class.normalize_phone('+573001234567', 'CO')

      expect(result.value).to eq('+573001234567')
      expect(result).to be_had_prefix
    end

    it 'detecta el prefijo pegado sin + y no lo duplica' do
      result = described_class.normalize_phone('573001234567', 'CO')

      expect(result.value).to eq('+573001234567')
      expect(result).to be_had_prefix
    end

    it 'usa el prefijo del país elegido, no el que sugiere el número' do
      # El mismo número local con dos países distintos da dos teléfonos distintos.
      expect(described_class.normalize_phone('3001234567', 'AF').value).to eq('+933001234567')
      expect(described_class.normalize_phone('3001234567', 'CO').value).to eq('+573001234567')
    end

    it 'quita separadores y ceros de marcación nacional' do
      expect(described_class.normalize_phone('(300) 123-4567', 'CO').value).to eq('+573001234567')
      expect(described_class.normalize_phone('03001234567', 'CO').value).to eq('+573001234567')
    end

    it 'devuelve nil cuando no se puede formar un E.164 válido' do
      expect(described_class.normalize_phone('no-es-un-numero', 'CO').value).to be_nil
      expect(described_class.normalize_phone('', 'CO').status).to eq(:blank)
    end

    it 'no adivina prefijo cuando el país es inválido' do
      result = described_class.normalize_phone('3001234567', 'XX')

      # Sin país, el número solo vale si ya es E.164 por sí mismo.
      expect(result.value).to eq('+3001234567')
      expect(result).to be_had_prefix
    end

    it 'trata como distintos dos números que difieren en un dígito' do
      a = described_class.normalize_phone('3001234567', 'CO').value
      b = described_class.normalize_phone('3001234568', 'CO').value

      expect(a).not_to eq(b)
    end
  end

  describe '.normalize_email' do
    it 'normaliza a minúsculas y recorta espacios' do
      expect(described_class.normalize_email('  Juan@Example.COM ')).to eq('juan@example.com')
    end

    it 'devuelve nil para correos inválidos o vacíos' do
      expect(described_class.normalize_email('no-es-correo')).to be_nil
      expect(described_class.normalize_email('')).to be_nil
    end
  end

  describe '.existing_index y .match_existing' do
    let(:account) { create(:account) }
    let(:other_account) { create(:account) }

    it 'encuentra contactos existentes por teléfono y por correo' do
      by_phone = create(:contact, account: account, phone_number: '+573001234567')
      by_email = create(:contact, account: account, email: 'ya@example.com')

      index = described_class.existing_index(account, phones: ['+573001234567'], emails: ['ya@example.com'])

      expect(described_class.match_existing(index, phone: '+573001234567')).to eq(by_phone)
      expect(described_class.match_existing(index, email: 'ya@example.com')).to eq(by_email)
    end

    it 'nunca cruza cuentas' do
      create(:contact, account: other_account, phone_number: '+573001234567')

      index = described_class.existing_index(account, phones: ['+573001234567'])

      expect(described_class.match_existing(index, phone: '+573001234567')).to be_nil
    end
  end

  describe '.valid_country?' do
    it 'acepta ISO conocidos y rechaza el resto' do
      expect(described_class).to be_valid_country('CO')
      expect(described_class).to be_valid_country('af')
      expect(described_class).not_to be_valid_country('XX')
      expect(described_class).not_to be_valid_country('')
    end
  end
end
