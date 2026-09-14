# frozen_string_literal: true

require 'rails_helper'

describe Jabvox::PhoneParts do
  describe '.split' do
    it 'separa el prefijo del número local' do
      expect(described_class.split('+573001234567')).to eq(
        country_code: '+57', national: '3001234567', e164: '+573001234567'
      )
    end

    it 'elige el prefijo MÁS LARGO que encaje' do
      # +1684 es Samoa Americana; partirlo como +1 daría un número local erróneo.
      expect(described_class.split('+16847331234')[:country_code]).to eq('+1684')
    end

    it 'funciona con prefijos de un solo dígito' do
      expect(described_class.split('+15417543010')).to include(
        country_code: '+1', national: '5417543010'
      )
    end

    it 'devuelve nil cuando no es un E.164' do
      expect(described_class.split('3001234567')).to be_nil
      expect(described_class.split('no-es-numero')).to be_nil
      expect(described_class.split(nil)).to be_nil
    end
  end

  describe '.join' do
    it 'arma el E.164 desde el país y el número local' do
      expect(described_class.join('CO', '3001234567')).to eq('+573001234567')
    end

    it 'el prefijo sale del país, no del número' do
      expect(described_class.join('AF', '3001234567')).to eq('+933001234567')
    end

    it 'devuelve nil si no se puede formar un número válido' do
      expect(described_class.join('CO', 'abc')).to be_nil
      expect(described_class.join('XX', '')).to be_nil
    end
  end

  describe 'ida y vuelta' do
    it 'join y split son consistentes entre sí' do
      e164 = described_class.join('CO', '3001234567')

      expect(described_class.split(e164)).to include(
        country_code: '+57', national: '3001234567'
      )
    end
  end
end
