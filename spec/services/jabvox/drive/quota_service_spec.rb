# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::Drive::QuotaService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account) }

  # Fija una cuota finita en bytes sin depender del plan (el enterprise mod puede
  # restringir las claves de limits en algunos entornos de test).
  def with_quota(bytes)
    allow_any_instance_of(described_class).to receive(:quota_bytes).and_return(bytes)
  end

  describe '#unlimited?' do
    it 'es ilimitado cuando storage_gb es 0' do
      with_quota(0)
      expect(service.unlimited?).to be(true)
    end
  end

  describe 'reserva / commit / release' do
    before { with_quota(1_000_000) }

    it 'reserva cuando cabe y rechaza cuando no' do
      expect(service.reserve!(600_000)).to be(true)
      expect(service.committed_bytes).to eq(600_000)
      expect(service.reserve!(600_000)).to be(false) # no cabe
      expect(service.committed_bytes).to eq(600_000)
      expect(service.reserve!(400_000)).to be(true)  # completa exacto
      expect(service.committed_bytes).to eq(1_000_000)
    end

    it 'commit pasa de reserved a used' do
      service.reserve!(500_000)
      service.commit!(500_000)
      expect(service.used_bytes).to eq(500_000)
      expect(service.reserved_bytes).to eq(0)
    end

    it 'release libera la reserva' do
      service.reserve!(500_000)
      service.release!(500_000)
      expect(service.reserved_bytes).to eq(0)
      expect(service.used_bytes).to eq(0)
    end

    it 'nunca deja reserved/used negativos' do
      service.release!(999)
      service.decrement_used!(999)
      expect(service.reserved_bytes).to eq(0)
      expect(service.used_bytes).to eq(0)
    end
  end

  describe 'reservas concurrentes (condición de carrera)' do
    it 'no supera la cuota aunque compitan muchas cargas' do
      quota = 1_000_000
      chunk = 100_000
      account # materializa antes de los hilos
      JabvoxDriveStorageAccount.find_or_create_by!(account_id: account.id)

      granted = Concurrent::AtomicFixnum.new(0)
      threads = 20.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            svc = described_class.new(Account.find(account.id))
            allow(svc).to receive(:quota_bytes).and_return(quota)
            granted.increment if svc.reserve!(chunk)
          end
        end
      end
      threads.each(&:join)

      final = JabvoxDriveStorageAccount.find_by(account_id: account.id)
      expect(granted.value).to be <= (quota / chunk)
      expect(final.reserved_bytes).to be <= quota
    end
  end

  describe '#recalculate!' do
    before { with_quota(10_000_000) }

    it 'recalcula used y overflow desde las filas reales' do
      create(:jabvox_drive_file, account: account, bucket: 'primary', byte_size: 300, status: :available)
      create(:jabvox_drive_file, account: account, bucket: 'overflow', byte_size: 500, status: :restricted)
      service.recalculate!
      expect(service.used_bytes).to eq(300)
      expect(service.overflow_bytes).to eq(500)
      expect(service.reserved_bytes).to eq(0)
    end
  end
end
