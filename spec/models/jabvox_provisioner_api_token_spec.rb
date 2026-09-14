# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JabvoxProvisionerApiToken do
  def create_token(allowed_ips: [], permissions: {})
    described_class.generate!(created_by_id: nil, allowed_ips: allowed_ips, permissions: permissions).first
  end

  describe 'token único' do
    it 'revoca el anterior al generar uno nuevo (máx 1 activo)' do
      first = create_token
      second = create_token

      expect(first.reload.status_jabvox).to eq('revoked')
      expect(second.reload.status_jabvox).to eq('active')
      expect(described_class.active.count).to eq(1)
    end

    it 'guarda solo el hash: el token en claro nunca se persiste' do
      _record, plaintext, = described_class.generate!(created_by_id: nil)

      expect(described_class.active.first.token_hash_jabvox).to eq(Digest::SHA256.hexdigest(plaintext))
      expect(described_class.active.first.attributes.values.map(&:to_s)).not_to include(plaintext)
    end

    it 'autentica el token correcto y rechaza uno alterado' do
      _record, plaintext, = described_class.generate!(created_by_id: nil)

      expect(described_class.authenticate(plaintext)).to be_present
      expect(described_class.authenticate("#{plaintext}x")).to be_nil
      expect(described_class.authenticate(nil)).to be_nil
    end
  end

  describe '#ip_allowed?' do
    it 'acepta una IP exacta de la allowlist' do
      token = create_token(allowed_ips: ['10.147.100.1'])

      expect(token.ip_allowed?('10.147.100.1')).to be(true)
      expect(token.ip_allowed?('10.147.100.2')).to be(false)
    end

    it 'acepta cualquier IP dentro de un rango CIDR de ZeroTier' do
      token = create_token(allowed_ips: ['10.147.0.0/16'])

      expect(token.ip_allowed?('10.147.100.1')).to be(true)
      expect(token.ip_allowed?('10.147.255.254')).to be(true)
      expect(token.ip_allowed?('10.148.0.1')).to be(false)
    end

    it 'bloquea todo cuando la allowlist está vacía' do
      expect(create_token(allowed_ips: []).ip_allowed?('10.147.100.1')).to be(false)
    end

    it 'ignora entradas malformadas en vez de conceder acceso' do
      token = create_token(allowed_ips: ['no-es-una-ip'])

      expect(token.ip_allowed?('10.147.100.1')).to be(false)
    end

    it 'nunca acepta la ruta por defecto como comodín' do
      token = create_token(allowed_ips: ['0.0.0.0/0'])

      expect(token.ip_allowed?('8.8.8.8')).to be(false)
    end

    it 'no cruza familias: un rango IPv6 no cubre una IPv4' do
      token = create_token(allowed_ips: ['::/8'])

      expect(token.ip_allowed?('10.147.100.1')).to be(false)
    end
  end

  describe '#allows? y sanitize_permissions' do
    it 'concede solo lo marcado en el checklist' do
      token = create_token(permissions: { 'accounts' => %w[view edit] })

      expect(token.allows?('accounts', 'view')).to be(true)
      expect(token.allows?('accounts', 'edit')).to be(true)
      expect(token.allows?('accounts', 'create')).to be(false)
      expect(token.allows?('users', 'view')).to be(false)
    end

    it 'nunca concede delete aunque se pida explícitamente' do
      token = create_token(permissions: { 'accounts' => %w[view delete destroy] })

      expect(token.permissions_jabvox['accounts']).to eq(['view'])
      expect(token.allows?('accounts', 'delete')).to be(false)
    end

    it 'degrada los recursos de solo lectura a view aunque se pida edit/create' do
      token = create_token(permissions: { 'transactions' => %w[view edit create] })

      expect(token.permissions_jabvox['transactions']).to eq(['view'])
      expect(token.allows?('transactions', 'edit')).to be(false)
    end

    it 'descarta recursos desconocidos' do
      token = create_token(permissions: { 'inventado' => ['view'] })

      expect(token.permissions_jabvox).not_to have_key('inventado')
      expect(token.allows?('inventado', 'view')).to be(false)
    end

    it 'un token revocado no permite nada' do
      token = create_token(permissions: { 'accounts' => ['view'] })
      token.revoke!

      expect(token.allows?('accounts', 'view')).to be(false)
    end
  end

  describe '#safe_summary' do
    it 'nunca expone el token ni el secreto de firma' do
      token = create_token(allowed_ips: ['10.147.0.0/16'])
      summary = token.safe_summary

      expect(summary.keys).not_to include(:token_hash, :signing_secret)
      expect(summary.to_s).not_to include(token.token_hash_jabvox)
      expect(summary[:allowed_ips]).to eq(['10.147.0.0/16'])
    end
  end
end
