require 'rails_helper'

RSpec.describe Jabvox::Tickets::DueAtCalculator do
  describe '#call sin horario laboral (24/7 lineal)' do
    it 'suma los minutos de forma corrida' do
      from = Time.utc(2026, 1, 5, 10, 0) # lunes 10:00
      due = described_class.new(120, from: from, config: nil).call
      expect(due).to be_within(1.second).of(from + 120.minutes)
    end
  end

  describe '#call con horario laboral' do
    let(:config) do
      instance_double(
        JabvoxTicketHelpdeskConfig,
        business_hours_jabvox: {
          'enabled' => true, 'days' => [1, 2, 3, 4, 5],
          'start_minute' => 540, 'end_minute' => 1080, 'time_zone' => 'UTC'
        }
      )
    end

    it 'no cuenta las horas fuera de jornada' do
      # Viernes 17:00 UTC, faltan 60 min de jornada (cierra 18:00). Pedir 120 min de SLA
      # consume 60 el viernes y debe saltar al lunes 09:00 + 60 min = lunes 10:00.
      from = Time.utc(2026, 1, 2, 17, 0) # viernes 17:00
      due = described_class.new(120, from: from, config: config).call
      expect(due).to eq(Time.utc(2026, 1, 5, 10, 0)) # lunes 10:00
    end

    it 'arranca en el inicio de jornada si el ticket entra de madrugada' do
      from = Time.utc(2026, 1, 5, 3, 0) # lunes 03:00 (antes de abrir)
      due = described_class.new(60, from: from, config: config).call
      expect(due).to eq(Time.utc(2026, 1, 5, 10, 0)) # 09:00 + 60 min
    end

    it 'salta el fin de semana' do
      from = Time.utc(2026, 1, 2, 17, 30) # viernes 17:30, quedan 30 min
      due = described_class.new(30, from: from, config: config).call
      expect(due).to eq(Time.utc(2026, 1, 2, 18, 0)) # justo al cierre del viernes
    end

    it 'cae a lineal si el horario está deshabilitado' do
      disabled = instance_double(
        JabvoxTicketHelpdeskConfig,
        business_hours_jabvox: { 'enabled' => false }
      )
      from = Time.utc(2026, 1, 2, 17, 0)
      due = described_class.new(120, from: from, config: disabled).call
      expect(due).to be_within(1.second).of(from + 120.minutes)
    end
  end
end
