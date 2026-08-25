# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::Hermes::Authorizer do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:other_account) { create(:account) }
  let(:outsider) { create(:user, account: other_account) }

  def grant!(target_user, target_account, *perms)
    JabvoxHermesUserPermission.create!(account: target_account, user: target_user,
                                       permissions_jabvox: perms)
  end

  describe '#authorize' do
    it 'permite una tool core con el permiso adecuado' do
      grant!(user, account, 'read')
      decision = described_class.new(account: account, user: user).authorize('get_labels')
      expect(decision).to be_allowed
    end

    it 'rechaza una tool desconocida (whitelist)' do
      grant!(user, account, 'admin')
      decision = described_class.new(account: account, user: user).authorize('rm_rf')
      expect(decision).not_to be_allowed
      expect(decision.reason).to match(/desconocida/)
    end

    it 'rechaza a un usuario que no pertenece a la cuenta (anti cross-account)' do
      grant!(outsider, account, 'read') # aunque tuviera permiso en la fila...
      decision = described_class.new(account: account, user: outsider).authorize('get_labels')
      expect(decision).not_to be_allowed
      expect(decision.reason).to match(/no pertenece/)
    end

    it 'rechaza cuando falta el permiso granular' do
      grant!(user, account, 'read')
      decision = described_class.new(account: account, user: user).authorize('create_label')
      expect(decision).not_to be_allowed
    end

    it 'NIVEL 1.5: niega una tool de módulo si el módulo está apagado en la cuenta' do
      grant!(user, account, 'read')
      allow(account).to receive(:feature_enabled?).with('jabvox_dialer').and_return(false)
      decision = described_class.new(account: account, user: user).authorize('get_dialer_campaigns')
      expect(decision).not_to be_allowed
      expect(decision.reason).to match(/módulo/)
    end

    it 'NIVEL 1.5: permite la tool de módulo si el módulo está habilitado y hay permiso' do
      grant!(user, account, 'read')
      allow(account).to receive(:feature_enabled?).with('jabvox_dialer').and_return(true)
      decision = described_class.new(account: account, user: user).authorize('get_dialer_campaigns')
      expect(decision).to be_allowed
    end

    it 'una tool core (feature=core) no requiere módulo, solo permiso' do
      grant!(user, account, 'read')
      decision = described_class.new(account: account, user: user).authorize('get_report_summary')
      expect(decision).to be_allowed
    end
  end

  describe '#allowed_tools' do
    it 'expone solo las tools permitidas' do
      grant!(user, account, 'read')
      tools = described_class.new(account: account, user: user).allowed_tools
      expect(tools).to include('get_labels')
      expect(tools).not_to include('create_label')
      expect(tools).not_to include('delete_label') # ya no existe en el registro
    end
  end
end
