# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::Drive::AuditService do
  let(:account) { create(:account) }
  let(:other) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:service) { described_class.new(account) }

  describe '#log' do
    it 'registra quién, qué y sobre qué recurso' do
      file = create(:jabvox_drive_file, account: account)
      log = service.log(action: 'download', actor: user, auditable: file,
                        metadata: { filename: 'x.pdf' })
      expect(log.action).to eq('download')
      expect(log.user_id).to eq(user.id)
      expect(log.auditable_type).to eq('JabvoxDriveFile')
      expect(log.auditable_id).to eq(file.id)
      expect(log.account_id).to eq(account.id)
    end

    it 'sanea metadatos sensibles (no guarda password/token/url/contenido)' do
      log = service.log(action: 'upload', actor: user,
                        metadata: { filename: 'ok.txt', password: 'x', token: 'y', url: 'z', content: 'c' })
      expect(log.metadata.keys).to eq(['filename'])
    end

    it 'nunca rompe la operación si el registro falla' do
      allow(JabvoxDriveAuditLog).to receive(:create!).and_raise(StandardError)
      expect { service.log(action: 'upload', actor: user) }.not_to raise_error
    end

    it 'es append-only (sin updated_at)' do
      expect(JabvoxDriveAuditLog.column_names).not_to include('updated_at')
    end
  end

  describe 'aislamiento' do
    it 'el historial de una cuenta no incluye el de otra' do
      create(:jabvox_drive_audit_log, account: account, action: 'upload')
      create(:jabvox_drive_audit_log, account: other, action: 'delete')
      expect(account.jabvox_drive_audit_logs.pluck(:action)).to eq(['upload'])
      expect(other.jabvox_drive_audit_logs.pluck(:action)).to eq(['delete'])
    end
  end
end
