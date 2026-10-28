# frozen_string_literal: true

require 'rails_helper'
require_relative '../spec_helper_nodes'

RSpec.describe Jabvox::Flows::Nodes::Jabvox::ConversationAddPrivateNoteNode do
  include NodeSpecHelpers

  let(:account) { create(:account) }
  let(:ctx) { build_ctx(account) }
  let(:channel) { create(:channel_api, account: account) }
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }

  it 'crea una nota PRIVADA (no se envía al cliente)' do
    result = run_node(described_class, ctx,
                      { 'conversationId' => conversation.display_id.to_s, 'content' => 'Pendiente de pago' })

    expect(result).to be_ok
    expect(result.output['private']).to be(true)
    msg = conversation.messages.last
    expect(msg.private).to be(true)
    expect(msg.content).to eq('Pendiente de pago')
  end

  it 'exige contenido' do
    expect(run_node(described_class, ctx, { 'conversationId' => conversation.display_id.to_s, 'content' => '  ' }).error)
      .to match(/no puede estar vac/)
  end

  it 'no ve conversaciones de otra cuenta' do
    otra = create(:conversation, account: create(:account))
    expect(run_node(described_class, ctx, { 'conversationId' => otra.display_id.to_s, 'content' => 'x' }).error)
      .to match(/no existe en esta cuenta/)
  end
end
