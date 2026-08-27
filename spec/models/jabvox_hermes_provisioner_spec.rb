# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JabvoxHermesProvisioner do
  describe '.instance (singleton único)' do
    it 'devuelve siempre el mismo registro' do
      a = described_class.instance
      b = described_class.instance
      expect(a.id).to eq(b.id)
      expect(described_class.count).to eq(1)
    end
  end

  describe '#valid_callback? (doble validación)' do
    let(:account) { create(:account) }
    let(:service_user) { create(:user, account: account) }
    let(:provisioner) do
      p = described_class.instance
      p.mark_connected!(base_url: 'http://10.147.100.1:9119', service_token: 'tok-abc',
                        service_user: service_user, callback_secret: 'sec-xyz')
      p
    end

    it 'acepta token + usuario de servicio + secreto correctos' do
      expect(provisioner.valid_callback?(token: 'tok-abc', service_user_id: service_user.id, secret: 'sec-xyz'))
        .to be(true)
    end

    it 'rechaza si el token no coincide' do
      expect(provisioner.valid_callback?(token: 'malo', service_user_id: service_user.id, secret: 'sec-xyz'))
        .to be(false)
    end

    it 'rechaza si el usuario de servicio no coincide' do
      expect(provisioner.valid_callback?(token: 'tok-abc', service_user_id: 999_999, secret: 'sec-xyz'))
        .to be(false)
    end

    it 'rechaza si el secreto no coincide' do
      expect(provisioner.valid_callback?(token: 'tok-abc', service_user_id: service_user.id, secret: 'malo'))
        .to be(false)
    end

    it 'rechaza si no está conectado' do
      p = described_class.instance
      expect(p.valid_callback?(token: 't', service_user_id: 1, secret: 's')).to be(false)
    end
  end

  describe '#sessions_path' do
    it 'default /api/sessions' do
      expect(described_class.instance.sessions_path).to eq('/api/sessions')
    end
  end
end
