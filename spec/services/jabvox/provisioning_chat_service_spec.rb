# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::ProvisioningChatService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  describe '#handle' do
    context 'cuando la cuenta NO está ligada a un Hermes Aprovisionador' do
      it 'no relaya y avisa que falta ligar la cuenta' do
        allow(JabvoxHermesProvisionerLink).to receive(:active_for?).with(account.id).and_return(false)
        out = described_class.new(account: account, user: user).handle('levanta el hermes')
        expect(out[:reply]).to include('no está ligada')
        expect(out[:metadata][:ok]).to be(false)
      end
    end

    context 'cuando la cuenta SÍ está ligada' do
      let(:relay) { instance_double(Jabvox::Hermes::ProvisionerChatRelay) }

      before do
        allow(JabvoxHermesProvisionerLink).to receive(:active_for?).with(account.id).and_return(true)
        allow(Jabvox::Hermes::ProvisionerChatRelay).to receive(:new).and_return(relay)
      end

      it 'relaya el mensaje al aprovisionador y devuelve su respuesta' do
        allow(relay).to receive(:send_message).with('hola')
          .and_return(Jabvox::Hermes::ProvisionerChatRelay::Result.new(
                        success: true, text: 'respuesta del aprovisionador'
                      ))
        out = described_class.new(account: account, user: user).handle('hola')
        expect(out[:reply]).to eq('respuesta del aprovisionador')
        expect(out[:metadata][:via]).to eq('provisioner')
      end

      it 'reporta el error si el aprovisionador falla' do
        allow(relay).to receive(:send_message)
          .and_return(Jabvox::Hermes::ProvisionerChatRelay::Result.new(success: false, error: 'timeout'))
        out = described_class.new(account: account, user: user).handle('hola')
        expect(out[:reply]).to include('no pudo responder')
        expect(out[:metadata][:ok]).to be(false)
      end
    end
  end
end
