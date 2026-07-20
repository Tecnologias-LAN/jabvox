# frozen_string_literal: true

require 'rails_helper'

# Regresión del loop de eventos del AMI listener:
#   - correlación de respuestas por ActionID (el Pong del Ping ya no lo roba un
#     Getvar; los eventos intermedios se despachan, nunca se pierden).
#   - OriginateResponse Failure cierra el log y no lo deja colgado.
# SubjectStub: los stubs de channel_var/notify son deliberados para aislar el loop
# de eventos del socket real y de Getvar en estos tests de unidad.
# rubocop:disable RSpec/SubjectStub
RSpec.describe Jabvox::AmiListenerService do
  subject(:listener) { described_class.new(account.id) }

  let(:account) { create(:account) }
  let(:agent) { create(:user) }

  # Socket falso que entrega líneas AMI predefinidas. IO.select se stubbea a "listo".
  def fake_socket(lines)
    sock = Object.new
    buffer = lines.dup
    sock.define_singleton_method(:gets) { buffer.shift }
    sock.define_singleton_method(:write) { |*| nil }
    sock
  end

  before { allow(IO).to receive(:select).and_return([true]) }

  describe 'await_response (correlación por ActionID)' do
    it 'devuelve la respuesta con el ActionID esperado y despacha los eventos intermedios' do
      lines = [
        "Event: Newchannel\r\n", "Channel: SIP/x-1\r\n", "\r\n",
        "Response: Success\r\n", "ActionID: jbx-#{account.id}-1\r\n", "Ping: Pong\r\n", "\r\n"
      ]
      listener.instance_variable_set(:@socket, fake_socket(lines))
      expect(listener).to receive(:dispatch_event).with(hash_including('event' => 'Newchannel'))

      aid = listener.send(:next_action_id)
      resp = listener.send(:await_response, aid)
      expect(resp['actionid']).to eq("jbx-#{account.id}-1")
      expect(resp['response']).to eq('Success')
    end

    it 'no confunde el Pong con la respuesta de otra acción sin ActionID' do
      lines = [
        "Response: Success\r\n", "ActionID: jbx-#{account.id}-1\r\n", "\r\n"
      ]
      listener.instance_variable_set(:@socket, fake_socket(lines))
      aid = listener.send(:next_action_id)
      expect(listener.send(:await_response, aid)['actionid']).to eq("jbx-#{account.id}-1")
    end
  end

  describe '#handle_originate_response' do
    let(:campaign) do
      JabvoxDialerCampaign.create!(account_id: account.id, name_jabvox: 'C', status_jabvox: 'active',
                                   dial_mode_jabvox: 'one_by_one')
    end
    let(:cc) do
      JabvoxDialerCampaignContact.create!(account_id: account.id, jabvox_dialer_campaign_id: campaign.id,
                                          phone_jabvox: '3001112233', status_jabvox: 'calling')
    end
    let!(:log) do
      JabvoxDialerCallLog.create!(account_id: account.id, jabvox_dialer_campaign_id: campaign.id,
                                  jabvox_dialer_campaign_contact_id: cc.id, agent_id_jabvox: agent.id,
                                  phone_jabvox: '3001112233',
                                  status_jabvox: 'initiated', started_at_jabvox: Time.current)
    end

    it 'cierra el log como failed cuando el Originate falla' do
      event = { 'response' => 'Failure', 'channel' => 'SIP/x-1', 'reason' => '1' }
      # El marcador del log llega por channel_var; lo stubbeamos para no depender de Getvar.
      allow(listener).to receive(:channel_var).and_return(log.id.to_s)
      allow(listener).to receive(:channel_belongs_to_account?).and_return(true)
      allow(listener).to receive(:notify_dialer_call_ended)

      listener.send(:handle_originate_response, event)

      expect(log.reload.status_jabvox).to eq('failed')
      expect(log.ended_at_jabvox).to be_present
      expect(cc.reload.status_jabvox).to eq('failed')
    end

    it 'ignora un OriginateResponse Success' do
      event = { 'response' => 'Success', 'channel' => 'SIP/x-1' }
      expect(listener).not_to receive(:close_dialer_log)
      listener.send(:handle_originate_response, event)
    end
  end
end
# rubocop:enable RSpec/SubjectStub
