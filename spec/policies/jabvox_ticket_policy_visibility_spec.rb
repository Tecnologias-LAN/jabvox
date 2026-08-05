require 'rails_helper'

# Verifica el knob de visibilidad del resolver (config del helpdesk):
#   assigned_only → el agente ve solo lo asignado a él
#   full_inbox    → el agente ve la bandeja completa de la cuenta gestora
RSpec.describe JabvoxTicketPolicy do
  subject(:resolved) { described_class::Scope.new(context, JabvoxTicket.all).resolve }

  let(:manager_account) { create(:account) }
  # Ticket ajeno (no asignado al agente) en la cuenta cliente.
  let!(:foreign_ticket) do
    create(:jabvox_ticket, account: client_account, requester: other_requester)
  end
  let(:context) do
    { user: agent, account: manager_account,
      account_user: manager_account.account_users.find_by(user: agent) }
  end
  let(:client_account) { create(:account) }
  let(:agent) { create(:user) }
  let(:other_requester) { create(:user) }

  let!(:config) do # rubocop:disable RSpec/LetSetup -- crea la config gestora que la policy consulta
    create(:jabvox_ticket_helpdesk_config, account: manager_account,
                                           resolver_visibility_jabvox: visibility)
  end

  before do
    create(:account_user, account: manager_account, user: agent, role: :agent)
  end

  context 'with assigned_only' do
    let(:visibility) { :assigned_only }

    it 'el agente NO ve tickets ajenos' do
      expect(resolved).not_to include(foreign_ticket)
    end
  end

  context 'with full_inbox' do
    let(:visibility) { :full_inbox }

    it 'el agente ve la bandeja completa' do
      expect(resolved).to include(foreign_ticket)
    end
  end
end
