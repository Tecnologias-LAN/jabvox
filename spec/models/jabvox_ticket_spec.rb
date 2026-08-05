# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JabvoxTicket, type: :model do
  let(:account) { create(:account) }
  let(:requester) { create(:user, account: account) }
  let(:agent) { create(:user, account: account) }
  # Los temas están centralizados en la cuenta gestora del helpdesk.
  let(:manager_account) { create(:account) }
  let(:category) do
    create(:jabvox_ticket_category, account: manager_account, category_type_jabvox: :incident,
                                    sla_resolution_minutes_jabvox: 120)
  end

  before { create(:jabvox_ticket_helpdesk_config, account: manager_account) }

  describe 'creation' do
    it 'assigns a sequential display_id per account' do
      t1 = create(:jabvox_ticket, account: account, requester: requester)
      t2 = create(:jabvox_ticket, account: account, requester: requester)
      expect([t1.display_id_jabvox, t2.display_id_jabvox]).to eq([1, 2])
    end

    it 'denormalizes category_type and sets due_at from SLA' do
      t = create(:jabvox_ticket, account: account, requester: requester, category: category)
      expect(t.category_type_jabvox).to eq('incident')
      expect(t.due_at_jabvox).to be_within(1.minute).of(t.created_at + 120.minutes)
    end

    it 'requires a title' do
      expect(build(:jabvox_ticket, account: account, requester: requester, title_jabvox: nil)).not_to be_valid
    end
  end

  describe 'lifecycle' do
    let(:ticket) { create(:jabvox_ticket, account: account, requester: requester) }

    it 'assign_to! sets assignee and moves new->assigned, logging activity' do
      ticket.assign_to!(agent, actor: agent)
      expect(ticket.reload.assignee_id).to eq(agent.id)
      expect(ticket.status_jabvox).to eq('assigned')
      expect(ticket.activities.last.action_jabvox).to eq('assigned')
    end

    it 'resolve! stamps resolved_at, type and logs it' do
      ticket.resolve!(resolution: 'ok', resolution_type: :solved, actor: agent)
      expect(ticket.reload.status_jabvox).to eq('resolved')
      expect(ticket.resolved_at_jabvox).to be_present
      expect(ticket.resolution_type_jabvox).to eq('solved')
      expect(ticket.activities.pluck(:action_jabvox)).to include('resolved')
    end

    it 'reopen! increments the counter and clears close stamps' do
      ticket.resolve!(resolution: 'ok', resolution_type: :solved)
      ticket.reopen!(actor: agent)
      expect(ticket.reload.status_jabvox).to eq('reopened')
      expect(ticket.reopened_count_jabvox).to eq(1)
      expect(ticket.resolved_at_jabvox).to be_nil
    end

    it 'rate! stores the satisfaction survey' do
      ticket.rate!(rating: 4, comment: 'bien', actor: requester)
      expect(ticket.reload.satisfaction_rating_jabvox).to eq(4)
    end
  end

  describe 'scopes' do
    it 'overdue returns open tickets past due_at' do
      overdue = create(:jabvox_ticket, account: account, requester: requester,
                                       due_at_jabvox: 1.hour.ago)
      create(:jabvox_ticket, account: account, requester: requester, due_at_jabvox: 1.hour.from_now)
      expect(described_class.overdue).to contain_exactly(overdue)
    end
  end
end
