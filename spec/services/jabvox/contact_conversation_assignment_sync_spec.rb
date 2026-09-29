# frozen_string_literal: true

require 'rails_helper'

# Asignar el contacto arrastra sus conversaciones, sea cual sea su estado: al filtrar
# "mías" se espera encontrar también las resueltas.
RSpec.describe Jabvox::ContactConversationAssignmentSync, type: :model do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create(:inbox, account: account) }

  def conversation(status: :open)
    ci = create(:contact_inbox, contact: contact, inbox: inbox)
    create(:conversation, account: account, inbox: inbox,
                          contact: contact, contact_inbox: ci, status: status)
  end

  it 'asigna las conversaciones abiertas, resueltas y pospuestas' do
    convs = %i[open resolved pending].index_with { |status| conversation(status: status) }

    contact.update!(assignee_id: agent.id)

    convs.each_value { |c| expect(c.reload.assignee_id).to eq(agent.id) }
  end

  it 'desasignar el contacto desasigna sus conversaciones' do
    conv = conversation
    contact.update!(assignee_id: agent.id)

    contact.update!(assignee_id: nil)

    expect(conv.reload.assignee_id).to be_nil
  end

  # El sentido contrario ya lo cubre Jabvox::ConversationContactAssignment; juntos no deben
  # entrar en bucle, porque ninguno escribe donde el responsable ya coincide.
  it 'asignar la conversación asigna el contacto sin rebotar' do
    conv = conversation

    conv.update!(assignee_id: other_agent.id)

    expect(contact.reload.assignee_id).to eq(other_agent.id)
    expect(conv.reload.assignee_id).to eq(other_agent.id)
  end

  it 'no toca conversaciones de otro contacto' do
    ajeno = create(:contact, account: account)
    ci = create(:contact_inbox, contact: ajeno, inbox: inbox)
    conv_ajena = create(:conversation, account: account, inbox: inbox,
                                       contact: ajeno, contact_inbox: ci, status: :open)

    contact.update!(assignee_id: agent.id)

    expect(conv_ajena.reload.assignee_id).to be_nil
  end
end
