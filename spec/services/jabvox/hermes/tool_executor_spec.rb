# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::Hermes::ToolExecutor do
  let(:account) { create(:account) }
  # Admin: su rol concede las capacidades; el cruce de permisos de rol de Hermes pasa.
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:executor) { described_class.new(account: account, user: user) }

  def grant!(*perms)
    JabvoxHermesUserPermission.create!(account: account, user: user, permissions_jabvox: perms)
  end

  describe 'tool destructiva eliminada' do
    it "delete_label ya no existe → 'tool desconocida'" do
      grant!('admin')
      result = executor.execute('delete_label', id: 1)
      expect(result.status).to eq('forbidden')
      expect(result.error).to match(/desconocida/)
    end
  end

  describe 'autorización + ejecución' do
    it 'ejecuta create_label con permiso create' do
      grant!('create')
      result = executor.execute('create_label', title: 'nueva')
      expect(result).to be_success
      expect(result.data[:title]).to eq('nueva')
    end

    it 'rechaza create_label sin permiso' do
      grant!('read')
      result = executor.execute('create_label', title: 'X')
      expect(result.status).to eq('forbidden')
    end

    it 'audita cada ejecución (éxito)' do
      grant!('create')
      expect { executor.execute('create_label', title: 'Log') }
        .to change(JabvoxHermesActionLog, :count).by(1)
    end

    it 'audita los intentos prohibidos' do
      grant!('read')
      expect { executor.execute('create_label', title: 'x') }
        .to change { JabvoxHermesActionLog.where(status_jabvox: 'forbidden').count }.by(1)
    end
  end
end
