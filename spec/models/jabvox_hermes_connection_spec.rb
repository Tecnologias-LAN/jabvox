require 'rails_helper'

RSpec.describe JabvoxHermesConnection do
  let(:account) { create(:account) }

  def build_connection(allowed_ips: [], name: 'agente-1')
    described_class.new(
      account: account,
      name_jabvox: name,
      hermes_agent_name_jabvox: name,
      base_url_jabvox: 'https://hermes.example.com',
      allowed_ips_jabvox: allowed_ips
    )
  end

  describe '#ip_allowed?' do
    # Fail-closed: el action_token por sí solo no basta. Si se filtra, sin allowlist
    # serviría desde cualquier punto de internet.
    context 'when no IPs are declared' do
      it 'rejects every request' do
        connection = build_connection

        expect(connection.ip_allowed?('203.0.113.5')).to be(false)
        expect(connection.ip_allowed?('127.0.0.1')).to be(false)
      end
    end

    context 'with a single public IP' do
      let(:connection) { build_connection(allowed_ips: ['203.0.113.5']) }

      it 'accepts that exact IP' do
        expect(connection.ip_allowed?('203.0.113.5')).to be(true)
      end

      it 'rejects any other IP' do
        expect(connection.ip_allowed?('203.0.113.6')).to be(false)
        expect(connection.ip_allowed?('45.77.167.167')).to be(false)
      end
    end

    context 'with a CIDR range' do
      let(:connection) { build_connection(allowed_ips: ['203.0.113.0/24']) }

      it 'accepts an address inside the range' do
        expect(connection.ip_allowed?('203.0.113.42')).to be(true)
      end

      it 'rejects an address outside the range' do
        expect(connection.ip_allowed?('203.0.114.1')).to be(false)
      end
    end

    # Los Hermes desplegados sobre ZeroTier llegan con IP de la red virtual (rango privado).
    # Esta allowlist es de origen ENTRANTE, al revés que el guard SSRF: aquí una IP privada
    # es legítima y esperada.
    context 'with a ZeroTier private range' do
      let(:connection) { build_connection(allowed_ips: ['10.147.17.0/24']) }

      it 'accepts the Hermes reaching in over the virtual network' do
        expect(connection.ip_allowed?('10.147.17.8')).to be(true)
      end

      it 'rejects a private address outside the declared range' do
        expect(connection.ip_allowed?('10.147.18.8')).to be(false)
        expect(connection.ip_allowed?('192.168.1.10')).to be(false)
      end
    end

    context 'with several entries mixing public and ZeroTier addresses' do
      let(:connection) do
        build_connection(allowed_ips: ['203.0.113.5', '10.147.17.0/24'])
      end

      it 'accepts any of them' do
        expect(connection.ip_allowed?('203.0.113.5')).to be(true)
        expect(connection.ip_allowed?('10.147.17.99')).to be(true)
      end

      it 'still rejects everything else' do
        expect(connection.ip_allowed?('8.8.8.8')).to be(false)
      end
    end

    context 'with malformed input' do
      it 'rejects a blank or nonsense IP' do
        connection = build_connection(allowed_ips: ['203.0.113.5'])

        expect(connection.ip_allowed?(nil)).to be(false)
        expect(connection.ip_allowed?('')).to be(false)
        expect(connection.ip_allowed?('not-an-ip')).to be(false)
      end
    end

    it 'supports IPv6 entries' do
      connection = build_connection(allowed_ips: ['2001:db8::/32'])

      expect(connection.ip_allowed?('2001:db8::1')).to be(true)
      expect(connection.ip_allowed?('2001:dead::1')).to be(false)
    end
  end

  # Desactivar un agente debe cortarle el paso también por el token de conexión, igual que
  # ya hacía JabvoxHermesAgent.authenticate con el token de agente.
  describe '#action_agent' do
    let(:user) { create(:user, account: account) }
    let(:connection) do
      conn = build_connection(allowed_ips: ['203.0.113.5'])
      conn.save!
      conn
    end

    def link(agent)
      JabvoxHermesAgentConnection.create!(hermes_connection: connection, hermes_agent: agent)
    end

    it 'returns a linked active agent' do
      agent = JabvoxHermesAgent.create!(account: account, user: user,
                                        name_jabvox: 'activo', status_jabvox: 'active')
      link(agent)

      expect(connection.reload.action_agent).to eq(agent)
    end

    it 'ignores a disabled agent, leaving the connection unable to act' do
      agent = JabvoxHermesAgent.create!(account: account, user: user,
                                        name_jabvox: 'apagado', status_jabvox: 'disabled')
      link(agent)

      expect(connection.reload.action_agent).to be_nil
      expect(connection.action_user).to be_nil
    end
  end

  describe 'allowed_ips validation' do
    it 'accepts IPs and CIDR ranges' do
      connection = build_connection(allowed_ips: ['203.0.113.5', '10.147.17.0/24'])

      expect(connection).to be_valid
    end

    # Un typo dejaría fuera al Hermes real sin que nadie se entere: mejor fallar al guardar.
    it 'rejects a malformed entry' do
      connection = build_connection(allowed_ips: ['203.0.113.999'])

      expect(connection).not_to be_valid
      expect(connection.errors[:allowed_ips_jabvox]).to be_present
    end

    it 'allows an empty list (connection declared but not yet authorised)' do
      expect(build_connection(allowed_ips: [])).to be_valid
    end
  end
end
