# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::Softphone::CredentialsService do
  let(:account) { create(:account) }
  let(:user) { create(:user) }

  before { create(:account_user, account: account, user: user, role: :administrator) }

  describe '#call' do
    context 'with an operational config and a linked extension' do
      let!(:config) { create(:jabvox_softphone_config, account: account) }

      # La extensión sale de VoIP; el secreto SIP de la tabla del softphone.
      before do
        create(:jabvox_user_extension, account: account, user: user, extension_jabvox: '1001')
        create(:jabvox_softphone_extension, account: account, user: user)
      end

      it 'devuelve las credenciales SIP + ICE con TURN temporal', :aggregate_failures do
        result = described_class.new(account: account, user: user).call

        expect(result[:wss_url]).to eq(config.wss_url)
        expect(result[:sip_uri]).to eq('sip:1001@pbx.jabvox.com') # ext de VoIP
        expect(result[:auth_user]).to eq('1001')
        expect(result[:codecs]).to eq(%w[opus alaw])
        turn = result[:ice_servers].last
        expect(turn[:urls]).to eq(config.turn_url)
        expect(turn[:username]).to match(/\A\d+:1001\z/) # <expiry>:<extension>
        expect(turn[:credential]).to be_present
      end

      it 'la credencial TURN es HMAC-SHA1(base64) del username con el turn_secret' do
        result = described_class.new(account: account, user: user).call
        turn = result[:ice_servers].last
        expected = Base64.strict_encode64(
          OpenSSL::HMAC.digest('SHA1', config.turn_secret, turn[:username])
        )
        expect(turn[:credential]).to eq(expected)
      end
    end

    context 'without an operational config' do
      it 'rechaza si no hay config' do
        expect { described_class.new(account: account, user: user).call }
          .to raise_error(Jabvox::Softphone::CredentialsError, 'softphone_not_configured')
      end

      it 'rechaza si la config está deshabilitada' do
        create(:jabvox_softphone_config, account: account, enabled: false)
        expect { described_class.new(account: account, user: user).call }
          .to raise_error(Jabvox::Softphone::CredentialsError, 'softphone_not_configured')
      end
    end

    context 'without a linked extension' do
      it 'rechaza con no_extension_linked si el usuario no tiene extensión de VoIP' do
        create(:jabvox_softphone_config, account: account)
        expect { described_class.new(account: account, user: user).call }
          .to raise_error(Jabvox::Softphone::CredentialsError, 'no_extension_linked')
      end

      it 'rechaza con no_sip_credential si hay extensión VoIP pero no secreto SIP' do
        create(:jabvox_softphone_config, account: account)
        create(:jabvox_user_extension, account: account, user: user, extension_jabvox: '1001')
        expect { described_class.new(account: account, user: user).call }
          .to raise_error(Jabvox::Softphone::CredentialsError, 'no_sip_credential')
      end
    end
  end
end
