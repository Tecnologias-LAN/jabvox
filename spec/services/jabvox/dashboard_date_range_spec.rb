# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::DashboardDateRange do
  let(:account) { create(:account) }

  describe 'validating calendar-day ranges' do
    it 'includes both selected days and uses an exclusive next-day boundary' do
      range = described_class.new(account: account, date_from: '2025-03-01', date_to: '2025-03-03')

      expect(range.from).to eq(range.time_zone.local(2025, 3, 1))
      expect(range.to_exclusive).to eq(range.time_zone.local(2025, 3, 4))
      expect(range.days).to eq([Date.new(2025, 3, 1), Date.new(2025, 3, 2), Date.new(2025, 3, 3)])
    end

    it 'rejects values that contain a time or are not strings' do
      expect do
        described_class.new(account: account, date_from: '2025-03-01T12:00:00')
      end.to raise_error(ArgumentError, 'Las fechas deben tener formato AAAA-MM-DD')

      expect do
        described_class.new(account: account, date_from: ['2025-03-01'])
      end.to raise_error(ArgumentError, 'Las fechas deben tener formato AAAA-MM-DD')
    end

    it 'rejects invalid dates, reversed ranges, and ranges longer than the maximum' do
      expect do
        described_class.new(account: account, date_from: '2025-02-30')
      end.to raise_error(ArgumentError, 'La fecha no es válida')

      expect do
        described_class.new(account: account, date_from: '2025-03-02', date_to: '2025-03-01')
      end.to raise_error(ArgumentError, 'La fecha final no puede ser anterior a la fecha inicial')

      expect do
        described_class.new(account: account, date_from: '2024-01-01', date_to: '2025-01-02')
      end.to raise_error(ArgumentError, 'El rango máximo es de 366 días')
    end
  end
end
