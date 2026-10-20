require 'rails_helper'

RSpec.describe Jabvox::AudioFilenameParserService do
  let(:account) { create(:account) }

  def pattern(str, **extra)
    account.jabvox_audio_filename_patterns.create!({ name: 'p', pattern: str }.merge(extra))
  end

  describe 'pattern parsing (modelo)' do
    it 'parsea el formato real de LikeU (teléfono-campaña nombre)' do
      p = JabvoxAudioFilenamePattern.new(pattern: '{phone}-{campaign} {advisor_name}')
      result = p.parse('3016615126-AMP Paula Ramírez')
      expect(result).to eq('phone' => '3016615126', 'campaign' => 'AMP', 'advisor_name' => 'Paula Ramírez')
    end

    it 'parsea un formato con ids y fecha' do
      p = JabvoxAudioFilenamePattern.new(pattern: '{advisor_id}-{typification_id}-{date}-{call_id}')
      expect(p.parse('01-05-2026-7890')).to eq(
        'advisor_id' => '01', 'typification_id' => '05', 'date' => '2026', 'call_id' => '7890'
      )
    end

    it 'devuelve nil cuando el nombre no casa con el patrón' do
      p = JabvoxAudioFilenamePattern.new(pattern: '{phone}-{advisor_name}')
      expect(p.parse('sin guion aqui')).to be_nil
    end

    it 'rechaza campos no reconocidos en la validación' do
      p = JabvoxAudioFilenamePattern.new(account: account, name: 'x', pattern: '{foo}-{phone}')
      expect(p).not_to be_valid
      expect(p.errors[:pattern].join).to match(/no reconocidos: foo/)
    end
  end

  describe '#parse (vinculación)' do
    before do
      pattern('{phone}-{campaign} {advisor_name}')
    end

    it 'vincula al asesor SOLO si hay un mapeo explícito del nombre' do
      advisor = account.jabvox_audio_advisors.create!(name: 'Paula Ramírez')
      account.jabvox_audio_code_mappings.create!(kind: 'advisor', code: 'Paula Ramírez', advisor: advisor)
      result = described_class.new(account).parse('leads/3016615126-AMP Paula Ramírez.WAV')
      expect(result[:matched]).to be(true)
      expect(result[:phone]).to eq('3016615126')
      expect(result[:advisor]).to eq(advisor)
    end

    it 'NO asume el asesor cuando el código no está mapeado' do
      account.jabvox_audio_advisors.create!(name: 'Paula Ramírez')
      result = described_class.new(account).parse('leads/3016615126-AMP Paula Ramírez.WAV')
      expect(result[:matched]).to be(true)
      expect(result[:advisor]).to be_nil
    end

    it 'vincula la tipificación SOLO si hay un mapeo del código (p. ej. AMP)' do
      typ = account.jabvox_typifications.create!(name: 'Toma de pedido')
      account.jabvox_audio_code_mappings.create!(kind: 'typification', code: 'AMP', typification: typ)
      result = described_class.new(account).parse('3016615126-AMP Paula Ramírez.WAV')
      expect(result[:typification]).to eq(typ)
    end

    it 'NO asume la tipificación cuando el código no está mapeado' do
      account.jabvox_typifications.create!(name: 'Toma de pedido')
      result = described_class.new(account).parse('3016615126-AMP Paula Ramírez.WAV')
      expect(result[:typification]).to be_nil
    end

    it 'no casa ningún patrón → matched false, sin romper' do
      result = described_class.new(account).parse('archivo_raro.wav')
      expect(result[:matched]).to be(false)
      expect(result[:advisor]).to be_nil
    end
  end

  describe 'JabvoxAudioAdvisor.match' do
    let!(:advisor) { account.jabvox_audio_advisors.create!(name: 'Paula Ramírez', external_id: 'paramirez') }

    it 'empata por external_id exacto' do
      expect(JabvoxAudioAdvisor.match(account, 'paramirez')).to eq(advisor)
    end

    it 'empata por nombre exacto (case-insensitive)' do
      expect(JabvoxAudioAdvisor.match(account, 'paula ramírez')).to eq(advisor)
    end

    it 'empata por nombre contenido en un token más largo' do
      expect(JabvoxAudioAdvisor.match(account, 'AMP Paula Ramírez')).to eq(advisor)
    end

    it 'no empata token en blanco' do
      expect(JabvoxAudioAdvisor.match(account, '  ')).to be_nil
    end
  end
end
