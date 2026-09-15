# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::Provisioner::Executor do
  subject(:executor) { described_class.new(token: token, ip: '10.147.100.1') }

  let(:token) do
    JabvoxProvisionerApiToken.generate!(
      created_by_id: nil, allowed_ips: ['10.147.0.0/16'],
      permissions: { 'accounts' => %w[view] }
    ).first
  end

  describe 'catálogo de operaciones' do
    it 'no declara NINGUNA operación de borrado' do
      registry = Jabvox::Provisioner::OperationRegistry::OPERATIONS

      expect(registry.values.map { |m| m[:action] }.uniq).to all(be_in(%w[view edit create]))
      expect(registry.keys.grep(/delete|destroy|remove|purge|drop/i)).to be_empty
      expect(registry.values.map { |m| m[:handler].to_s }.grep(/delete|destroy/i)).to be_empty
    end

    it 'solo declara operaciones view para los recursos de solo lectura' do
      read_only = JabvoxProvisionerApiToken::READ_ONLY_RESOURCES
      offending = Jabvox::Provisioner::OperationRegistry::OPERATIONS.select do |_op, m|
        read_only.include?(m[:resource]) && m[:action] != 'view'
      end

      expect(offending).to be_empty
    end

    it 'todos los recursos declarados existen en el checklist del token' do
      resources = Jabvox::Provisioner::OperationRegistry::OPERATIONS.values.map { |m| m[:resource] }.uniq

      expect(resources - JabvoxProvisionerApiToken::RESOURCES).to be_empty
    end
  end

  describe '#call' do
    it 'rechaza una operación que no existe en la whitelist' do
      result = executor.call(operation: 'accounts.delete', params: {})

      expect(result).not_to be_ok
      expect(result.code).to eq('unknown_operation')
      expect(result.status).to eq(404)
    end

    it 'rechaza una operación cuyo permiso no está habilitado' do
      result = executor.call(operation: 'accounts.create', params: { 'name' => 'X' })

      expect(result).not_to be_ok
      expect(result.code).to eq('permission_denied')
      expect(result.status).to eq(403)
      expect(Account.find_by(name: 'X')).to be_nil
    end

    it 'ejecuta una operación permitida y la audita' do
      result = executor.call(operation: 'accounts.list', params: {})

      expect(result).to be_ok
      log = JabvoxProvisionerAuditLog.order(:id).last
      expect(log.outcome_jabvox).to eq('ok')
      expect(log.resource_jabvox).to eq('accounts')
    end

    it 'revalida el permiso FRESCO: quitarlo surte efecto de inmediato' do
      expect(executor.call(operation: 'accounts.list', params: {})).to be_ok

      token.update!(permissions_jabvox: {})

      expect(executor.call(operation: 'accounts.list', params: {})).not_to be_ok
    end

    it 'deniega todo si el token fue revocado' do
      token.revoke!

      result = executor.call(operation: 'accounts.list', params: {})

      expect(result).not_to be_ok
      expect(result.code).to eq('permission_denied')
    end

    it 'audita los intentos denegados' do
      executor.call(operation: 'accounts.create', params: {})

      log = JabvoxProvisionerAuditLog.order(:id).last
      expect(log.outcome_jabvox).to eq('denied')
      expect(log.reason_jabvox).to eq('permission_denied')
    end
  end

  describe 'auditoría' do
    it 'nunca persiste valores sensibles' do
      JabvoxProvisionerAuditLog.record!(
        token_id: token.id, resource: 'accounts', action: 'view', outcome: 'ok',
        reason: nil, ip: '10.147.100.1', status: 200,
        params: { 'api_key' => 'secreto-123', 'password' => 'p4ss', 'name' => 'visible' }
      )

      log = JabvoxProvisionerAuditLog.order(:id).last
      expect(log.params_jabvox['api_key']).to eq('[REDACTED]')
      expect(log.params_jabvox['password']).to eq('[REDACTED]')
      expect(log.params_jabvox['name']).to eq('visible')
    end
  end
end
