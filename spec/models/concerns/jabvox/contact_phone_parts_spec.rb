# frozen_string_literal: true

require 'rails_helper'

# El teléfono se guarda en tres piezas. phone_number (E.164) es la identidad;
# country_code y phone_national_jabvox se derivan de él automáticamente.
describe Jabvox::ContactPhoneParts do
  let(:account) { create(:account) }

  describe 'derivación automática al guardar' do
    it 'separa el prefijo y el número local a partir del E.164' do
      contact = create(:contact, account: account, phone_number: '+573001234567')

      expect(contact.phone_country_code_jabvox).to eq('+57')
      expect(contact.phone_national_jabvox).to eq('3001234567')
    end

    it 'recalcula las piezas cuando cambia el teléfono' do
      contact = create(:contact, account: account, phone_number: '+573001234567')

      contact.update!(phone_number: '+16847331234')

      expect(contact.reload.phone_country_code_jabvox).to eq('+1684')
      expect(contact.phone_national_jabvox).to eq('7331234')
    end

    it 'limpia el número local cuando se borra el teléfono' do
      contact = create(:contact, account: account, phone_number: '+573001234567')

      contact.update!(phone_number: nil)

      expect(contact.reload.phone_national_jabvox).to be_nil
    end

    it 'no toca las piezas si el teléfono no cambió' do
      contact = create(:contact, account: account, phone_number: '+573001234567')

      contact.update!(name: 'Otro nombre')

      expect(contact.reload.phone_national_jabvox).to eq('3001234567')
    end
  end

  describe '#assign_phone_from_parts' do
    it 'arma el E.164 desde el país y el número local' do
      contact = build(:contact, account: account)

      expect(contact.assign_phone_from_parts('CO', '3001234567')).to be(true)
      contact.save!

      expect(contact.phone_number).to eq('+573001234567')
      expect(contact.phone_country_code_jabvox).to eq('+57')
      expect(contact.phone_national_jabvox).to eq('3001234567')
    end

    it 'el prefijo sale del país elegido, no del número' do
      contact = build(:contact, account: account)
      contact.assign_phone_from_parts('AF', '3001234567')

      expect(contact.phone_number).to eq('+933001234567')
    end

    it 'devuelve false y no asigna nada si el número no es válido' do
      contact = build(:contact, account: account)

      expect(contact.assign_phone_from_parts('CO', 'abc')).to be(false)
      expect(contact.phone_number).to be_nil
    end
  end

  describe '#phone_parts_jabvox' do
    it 'devuelve las tres piezas juntas' do
      contact = create(:contact, account: account, phone_number: '+573001234567')

      expect(contact.phone_parts_jabvox).to eq(
        country_code: '+57', national: '3001234567', e164: '+573001234567'
      )
    end
  end

  describe 'identidad' do
    it 'la deduplicación sigue usando el E.164, no las piezas' do
      create(:contact, account: account, phone_number: '+573001234567')
      duplicate = build(:contact, account: account, phone_number: '+573001234567')

      expect(duplicate).not_to be_valid
    end
  end
end
