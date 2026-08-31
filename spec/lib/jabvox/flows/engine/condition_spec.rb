# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::Flows::Engine::Condition do
  describe 'igualdad y texto' do
    it 'compara numéricamente cuando ambos lados son números' do
      expect(described_class.evaluate('10', 'equals', 10)).to be(true)
      expect(described_class.evaluate(10, 'not_equals', 11)).to be(true)
    end

    it 'compara texto con trim e ignorando mayúsculas' do
      expect(described_class.evaluate('  Ana ', 'equals', 'ana')).to be(true)
      expect(described_class.evaluate('Telegram', 'contains', 'gram')).to be(true)
      expect(described_class.evaluate('Telegram', 'starts_with', 'tele')).to be(true)
      expect(described_class.evaluate('Telegram', 'ends_with', 'gram')).to be(true)
    end
  end

  describe 'operadores de orden' do
    it 'compara numéricamente cuando ambos lados son números' do
      expect(described_class.evaluate(2000, 'greater_than', '1000')).to be(true)
      expect(described_class.evaluate('500', 'less_than', 1000)).to be(true)
      expect(described_class.evaluate(1000, 'greater_or_equal', 1000)).to be(true)
    end

    # BUG HISTÓRICO: al caer a texto, 'telegram' > '1000' era TRUE
    # lexicográficamente, y un caso de switch capturaba CUALQUIER texto dejando
    # inalcanzables los casos siguientes y el `default`.
    it 'da FALSE si el derecho es numérico y el izquierdo no' do
      expect(described_class.evaluate('telegram', 'greater_than', '1000')).to be(false)
      expect(described_class.evaluate('telegram', 'greater_or_equal', 1000)).to be(false)
    end

    it 'mantiene la comparación de texto cuando NINGÚN lado es numérico' do
      expect(described_class.evaluate('b', 'greater_than', 'a')).to be(true)
    end
  end

  describe 'operadores de fecha' do
    it 'parsea fechas de verdad en date_after y date_before' do
      expect(described_class.evaluate('2026-08-27', 'date_after', '2026-01-01')).to be(true)
      expect(described_class.evaluate('2026-01-01', 'date_before', '2026-08-27')).to be(true)
      expect(described_class.evaluate('2026-08-27', 'date_equals', '2026-08-27')).to be(true)
    end

    it 'da false si algún lado no es una fecha parseable' do
      expect(described_class.evaluate('no es fecha', 'date_after', '2026-01-01')).to be(false)
    end

    # Contraste: `greater_than` NO parsea fechas, ordena TEXTO. Con formato ISO
    # el orden alfabético coincide con el cronológico y parece que funciona,
    # pero es una coincidencia del formato, no comparación de fechas.
    it 'greater_than ordena texto en vez de parsear fechas' do
      expect(described_class.evaluate('2026-08-27', 'greater_than', '2026-01-01')).to be(true)
      # Un formato no ISO delata que es orden alfabético: 01/12 < 02/01.
      expect(described_class.evaluate('01/12/2026', 'greater_than', '02/01/2026')).to be(false)
      # date_after sí parsea de verdad y da el orden cronológico correcto.
      expect(described_class.evaluate('2026-12-01', 'date_after', '2026-01-02')).to be(true)
    end
  end

  describe 'unarios y listas' do
    it 'evalúa vacío sobre null, cadena, array y objeto' do
      [nil, '', '   ', [], {}].each { |v| expect(described_class.evaluate(v, 'is_empty')).to be(true) }
      expect(described_class.evaluate('algo', 'is_not_empty')).to be(true)
    end

    it 'interpreta booleanos "humanos"' do
      %w[true 1 si sí yes on].each { |v| expect(described_class.evaluate(v, 'is_true')).to be(true) }
      %w[false 0 no off].each { |v| expect(described_class.evaluate(v, 'is_false')).to be(true) }
    end

    it 'evalúa listas separadas por comas' do
      expect(described_class.evaluate('ana', 'in_list', 'ana, beto, caro')).to be(true)
      expect(described_class.evaluate('zoe', 'not_in_list', 'ana, beto')).to be(true)
    end
  end

  describe 'robustez' do
    it 'nunca lanza: regex inválida y operador desconocido dan false' do
      expect(described_class.evaluate('texto', 'regex', '([')).to be(false)
      expect(described_class.evaluate('a', 'operador_inventado', 'b')).to be(false)
    end

    it 'acepta los alias heredados de la v2' do
      expect(described_class.evaluate(1, '==', 1)).to be(true)
      expect(described_class.evaluate('', 'isEmpty')).to be(true)
      expect(described_class.evaluate(5, '>', 2)).to be(true)
    end

    it 'aplica regex sin distinguir mayúsculas' do
      expect(described_class.evaluate('Ana Lopez', 'regex', '^ana')).to be(true)
    end
  end
end
