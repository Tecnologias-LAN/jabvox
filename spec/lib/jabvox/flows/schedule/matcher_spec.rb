# frozen_string_literal: true

require 'rails_helper'

# DISPARO PROGRAMADO con zonas horarias. El servidor corre en UTC: sin esto un
# "9am" configurado por el usuario disparaba a las 4am en Colombia.
RSpec.describe Jabvox::Flows::Schedule::Matcher do
  def config(params)
    Jabvox::Flows::Schedule::Config.from_params(params)
  end

  def fire?(params, instant)
    described_class.fire?(config(params), instant)
  end

  describe 'zona horaria (el bug que motivó la pieza)' do
    # 14:00 UTC son las 09:00 en Bogotá (UTC-5).
    let(:instante) { Time.utc(2026, 8, 27, 14, 0) }

    it 'dispara a las 9am de Bogotá cuando el servidor marca las 14:00 UTC' do
      expect(fire?({ 'mode' => 'daily', 'time' => '09:00', 'timezone' => 'America/Bogota' }, instante))
        .to be(true)
    end

    it 'NO dispara a esa hora si la configuración se interpreta en UTC' do
      expect(fire?({ 'mode' => 'daily', 'time' => '09:00' }, instante)).to be(false)
    end

    it 'sin zona horaria dispara cuando el reloj del SERVIDOR marca la hora' do
      expect(fire?({ 'mode' => 'daily', 'time' => '14:00' }, instante)).to be(true)
    end

    it 'degrada a la hora del servidor si la zona no se reconoce' do
      expect(fire?({ 'mode' => 'daily', 'time' => '14:00', 'timezone' => 'Marte/Olimpo' }, instante))
        .to be(true)
    end
  end

  describe 'modo minutes' do
    it 'dispara cada N minutos desde medianoche' do
      expect(fire?({ 'mode' => 'minutes', 'every' => 15 }, Time.utc(2026, 8, 27, 10, 30))).to be(true)
    end

    it 'no dispara en un minuto que no es múltiplo' do
      expect(fire?({ 'mode' => 'minutes', 'every' => 15 }, Time.utc(2026, 8, 27, 10, 31))).to be(false)
    end
  end

  describe 'modo hours' do
    it 'dispara en el minuto 0 de cada N horas' do
      expect(fire?({ 'mode' => 'hours', 'every' => 6 }, Time.utc(2026, 8, 27, 12, 0))).to be(true)
    end

    it 'no dispara fuera del minuto 0' do
      expect(fire?({ 'mode' => 'hours', 'every' => 6 }, Time.utc(2026, 8, 27, 12, 5))).to be(false)
    end
  end

  describe 'modo weekly' do
    # 2026-08-27 es jueves (ISO 4).
    it 'dispara en un día de la semana seleccionado' do
      expect(fire?({ 'mode' => 'weekly', 'time' => '10:00', 'weekdays' => [4] },
                   Time.utc(2026, 8, 27, 10, 0))).to be(true)
    end

    it 'no dispara en un día no seleccionado' do
      expect(fire?({ 'mode' => 'weekly', 'time' => '10:00', 'weekdays' => [1, 2] },
                   Time.utc(2026, 8, 27, 10, 0))).to be(false)
    end

    it 'trata el domingo como el día ISO 7' do
      expect(fire?({ 'mode' => 'weekly', 'time' => '10:00', 'weekdays' => [7] },
                   Time.utc(2026, 8, 30, 10, 0))).to be(true)
    end
  end

  describe 'modo monthly' do
    it 'dispara el día del mes configurado' do
      expect(fire?({ 'mode' => 'monthly', 'time' => '10:00', 'dayOfMonth' => 27 },
                   Time.utc(2026, 8, 27, 10, 0))).to be(true)
    end

    it 'ajusta al último día cuando el mes no tiene ese día' do
      # Febrero de 2026 tiene 28 días: un día 31 dispara el 28.
      expect(fire?({ 'mode' => 'monthly', 'time' => '10:00', 'dayOfMonth' => 31 },
                   Time.utc(2026, 2, 28, 10, 0))).to be(true)
    end
  end

  describe 'saneado de la configuración' do
    it 'aplica los valores por defecto ante params ilegibles' do
      cfg = config({ 'mode' => 'inventado', 'every' => -3, 'time' => '99:99' })

      expect(cfg.mode).to eq('daily')
      expect(cfg.every).to eq(1)
      expect(cfg.time).to eq('08:00')
    end

    it 'descarta los días de la semana fuera de rango' do
      expect(config({ 'weekdays' => [0, 3, 9] }).weekdays).to eq([3])
    end

    it 'no lanza ante una zona horaria inválida' do
      expect(config({ 'timezone' => 'Marte/Olimpo' }).timezone).to be_nil
    end
  end
end
