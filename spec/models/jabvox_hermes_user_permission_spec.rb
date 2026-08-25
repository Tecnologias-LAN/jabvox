# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JabvoxHermesUserPermission do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  describe 'catálogo de permisos' do
    it 'no incluye delete' do
      expect(described_class::PERMISSIONS).not_to include('delete')
    end

    it "'admin' no implica borrar" do
      expect(described_class::ADMIN_IMPLIES).not_to include('delete')
    end

    it 'rechaza guardar el permiso delete' do
      perm = described_class.new(account: account, user: user, permissions_jabvox: %w[delete])
      expect(perm).not_to be_valid
    end
  end

  describe '.allows?' do
    it 'concede read/create/write cuando están otorgados' do
      described_class.create!(account: account, user: user, permissions_jabvox: %w[read create write])
      expect(described_class.allows?(account.id, user.id, 'read')).to be(true)
      expect(described_class.allows?(account.id, user.id, 'create')).to be(true)
      expect(described_class.allows?(account.id, user.id, 'write')).to be(true)
    end

    it 'niega delete SIEMPRE, incluso con admin' do
      described_class.create!(account: account, user: user, permissions_jabvox: %w[admin])
      expect(described_class.allows?(account.id, user.id, 'delete')).to be(false)
      expect(described_class.allows?(account.id, user.id, 'destroy')).to be(false)
    end

    it "'admin' implica read/create/write/execute/configure (pero no delete)" do
      described_class.create!(account: account, user: user, permissions_jabvox: %w[admin])
      %w[read create write execute configure].each do |p|
        expect(described_class.allows?(account.id, user.id, p)).to be(true)
      end
      expect(described_class.allows?(account.id, user.id, 'delete')).to be(false)
    end

    it 'niega un permiso no otorgado' do
      described_class.create!(account: account, user: user, permissions_jabvox: %w[read])
      expect(described_class.allows?(account.id, user.id, 'write')).to be(false)
    end
  end
end
