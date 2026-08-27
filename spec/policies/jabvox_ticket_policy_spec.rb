# frozen_string_literal: true

require 'rails_helper'

# Los bloques `permissions :a, :b` comparten los mismos `it` a propósito (misma regla
# aplica a varias acciones); rubocop-rspec los ve como repetidos. Es intencional.
# rubocop:disable RSpec/RepeatedExample
RSpec.describe JabvoxTicketPolicy, type: :policy do
  subject(:policy) { described_class }

  # Cuenta gestora del helpdesk: sus admins son staff, sus agentes resolvers.
  let(:manager_account) { create(:account) }
  let(:staff) { create(:user, :administrator, account: manager_account) }
  let(:resolver) { create(:user, account: manager_account) }

  # Cuenta cliente: sus usuarios solo ven lo suyo.
  let(:client_account) { create(:account) }
  let(:owner) { create(:user, account: client_account) }
  let(:stranger) { create(:user, account: client_account) }

  let(:ticket) { create(:jabvox_ticket, account: client_account, requester: owner) }

  before { create(:jabvox_ticket_helpdesk_config, account: manager_account) }

  def ctx(user)
    { user: user, account: user.accounts.first, account_user: nil }
  end

  describe 'scope' do
    let!(:owner_ticket) { create(:jabvox_ticket, account: client_account, requester: owner) }
    let!(:other_ticket) { create(:jabvox_ticket, account: client_account, requester: stranger) }

    it 'staff sees all tickets' do
      scope = JabvoxTicketPolicy::Scope.new(ctx(staff), JabvoxTicket.all).resolve
      expect(scope).to include(owner_ticket, other_ticket)
    end

    it 'a plain user sees only their own tickets' do
      scope = JabvoxTicketPolicy::Scope.new(ctx(owner), JabvoxTicket.all).resolve
      expect(scope).to contain_exactly(owner_ticket)
    end
  end

  permissions :show? do
    it { expect(policy).to permit(ctx(staff), ticket) }       # staff ve todo
    it { expect(policy).to permit(ctx(owner), ticket) }       # dueño ve el suyo
    it { expect(policy).not_to permit(ctx(stranger), ticket) } # ajeno NO
  end

  permissions :resolve?, :change_status?, :assign? do
    it { expect(policy).to permit(ctx(staff), ticket) }        # staff gestiona
    it { expect(policy).not_to permit(ctx(owner), ticket) }    # dueño no resuelve
    it { expect(policy).not_to permit(ctx(resolver), ticket) } # resolver sin asignación no

    it 'resolver assigned to the ticket can manage it' do
      ticket.update!(assignee_id: resolver.id)
      expect(policy).to permit(ctx(resolver), ticket)
    end
  end

  permissions :destroy?, :metrics? do
    it { expect(policy).to permit(ctx(staff), ticket) }
    it { expect(policy).not_to permit(ctx(owner), ticket) }
  end

  permissions :rate? do
    it { expect(policy).to permit(ctx(owner), ticket) }        # solo el dueño califica
    it { expect(policy).not_to permit(ctx(staff), ticket) }
  end
end
# rubocop:enable RSpec/RepeatedExample
