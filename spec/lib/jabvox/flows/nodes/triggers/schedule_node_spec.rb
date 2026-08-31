# frozen_string_literal: true

require 'rails_helper'

# Disparadores: no tienen handler, pero SÍ deciden si les toca disparar.
RSpec.describe Jabvox::Flows::Nodes::Triggers::ScheduleNode do
  def node(params)
    Jabvox::Flows::Engine::Graph::Node.new(id: 't', type: 'trigger.schedule', params: params, data: {})
  end

  describe 'cada X minutos' do
    it 'dispara cuando ha pasado el intervalo' do
      config = node('mode' => 'minutes', 'every' => 10)

      expect(described_class.due?(config, last_run_at: 11.minutes.ago)).to be(true)
      expect(described_class.due?(config, last_run_at: 5.minutes.ago)).to be(false)
    end

    it 'dispara la primera vez, sin ejecución previa' do
      expect(described_class.due?(node('mode' => 'minutes', 'every' => 10))).to be(true)
    end
  end

  describe 'diario' do
    let(:tz) { 'America/Bogota' }
    let(:config) { node('mode' => 'daily', 'time' => '08:00', 'timezone' => tz) }

    it 'dispara pasada la hora del día' do
      now = ActiveSupport::TimeZone[tz].parse('2026-08-27 09:00')

      expect(described_class.due?(config, now: now)).to be(true)
    end

    it 'NO dispara antes de la hora' do
      now = ActiveSupport::TimeZone[tz].parse('2026-08-27 07:00')

      expect(described_class.due?(config, now: now)).to be(false)
    end

    it 'no repite dentro del mismo día' do
      now = ActiveSupport::TimeZone[tz].parse('2026-08-27 09:00')
      ya = ActiveSupport::TimeZone[tz].parse('2026-08-27 08:05')

      expect(described_class.due?(config, now: now, last_run_at: ya)).to be(false)
    end

    it 'la zona horaria manda: 08:00 en Bogotá no son las 08:00 en UTC' do
      # 13:00 UTC son las 08:00 en Bogotá: toca la de las 08:00, no la de las 20:00.
      now = Time.utc(2026, 8, 27, 13, 0)

      expect(described_class.due?(config, now: now)).to be(true)
      expect(described_class.due?(node('mode' => 'daily', 'time' => '20:00', 'timezone' => tz), now: now))
        .to be(false)
    end
  end

  describe 'semanal' do
    it 'solo dispara en los días elegidos' do
      config = node('mode' => 'weekly', 'time' => '08:00', 'weekdays' => [1], 'timezone' => 'UTC')

      expect(described_class.due?(config, now: Time.utc(2026, 8, 24, 9, 0))).to be(true)
      expect(described_class.due?(config, now: Time.utc(2026, 8, 25, 9, 0))).to be(false)
    end
  end

  describe 'mensual' do
    it 'dispara el día elegido' do
      config = node('mode' => 'monthly', 'time' => '08:00', 'dayOfMonth' => 5, 'timezone' => 'UTC')

      expect(described_class.due?(config, now: Time.utc(2026, 8, 5, 9, 0))).to be(true)
      expect(described_class.due?(config, now: Time.utc(2026, 8, 6, 9, 0))).to be(false)
    end

    it 'cae al ÚLTIMO día del mes cuando el mes no tiene ese día' do
      config = node('mode' => 'monthly', 'time' => '08:00', 'dayOfMonth' => 31, 'timezone' => 'UTC')

      expect(described_class.due?(config, now: Time.utc(2026, 2, 28, 9, 0))).to be(true)
    end
  end

  it 'una configuración ilegible cae al diario de las 08:00' do
    config = described_class.config_of(node('mode' => 'raro', 'time' => 'nope'))

    expect(config[:mode]).to eq('daily')
    expect(config[:time]).to eq([8, 0])
  end
end
