# frozen_string_literal: true

require 'rails_helper'

# Filtros server-side del listado de tickets (funcionan con paginación, no solo en
# el front): unassigned, due_today, assignee_id, status=open y búsqueda sin acentos.
RSpec.describe 'Jabvox Tickets filters', type: :request do
  let(:manager_account) { create(:account, jabvox_tickets_enabled_jabvox: true) }
  let(:staff) { create(:user, account: manager_account, role: :administrator) }
  let(:account) { create(:account, jabvox_tickets_enabled_jabvox: true) }
  let(:requester) { create(:user, account: account, role: :agent) }
  let(:agent) { create(:user, account: manager_account, role: :agent) }

  before do
    create(:jabvox_ticket_helpdesk_config, account: manager_account,
                                           business_hours_jabvox: { 'time_zone' => 'America/Bogota' })
  end

  def index_url = "/api/v1/accounts/#{manager_account.id}/jabvox/tickets/tickets"

  def ids_for(params)
    get index_url, params: params, headers: staff.create_new_auth_token, as: :json
    response.parsed_body['data'].map { |t| t['id'] }
  end

  describe 'unassigned' do
    let!(:unassigned_ticket) { create(:jabvox_ticket, account: account, requester: requester, assignee: nil) }
    let!(:assigned_ticket) do
      create(:jabvox_ticket, account: account, requester: requester, assignee: agent)
    end

    it 'devuelve solo los tickets sin asignar' do
      ids = ids_for(unassigned: true)
      expect(ids).to include(unassigned_ticket.id)
      expect(ids).not_to include(assigned_ticket.id)
    end
  end

  describe 'assignee_id' do
    let!(:mine) { create(:jabvox_ticket, account: account, requester: requester, assignee: agent) }
    let!(:other) { create(:jabvox_ticket, account: account, requester: requester, assignee: nil) }

    it 'filtra por el agente asignado' do
      ids = ids_for(assignee_id: agent.id)
      expect(ids).to contain_exactly(mine.id)
      expect(ids).not_to include(other.id)
    end
  end

  describe 'status=open' do
    let!(:open_ticket) { create(:jabvox_ticket, account: account, requester: requester) }
    let!(:closed_ticket) do
      t = create(:jabvox_ticket, account: account, requester: requester)
      t.change_status!('closed')
      t
    end

    it 'devuelve solo tickets abiertos' do
      ids = ids_for(status: 'open')
      expect(ids).to include(open_ticket.id)
      expect(ids).not_to include(closed_ticket.id)
    end
  end

  describe 'due_today' do
    let(:zone) { ActiveSupport::TimeZone['America/Bogota'] }
    let!(:due_today_ticket) do
      create(:jabvox_ticket, account: account, requester: requester,
                             due_at_jabvox: zone.now.change(hour: 15))
    end
    let!(:due_tomorrow_ticket) do
      create(:jabvox_ticket, account: account, requester: requester,
                             due_at_jabvox: zone.now.tomorrow.change(hour: 15))
    end

    it 'devuelve solo los que vencen hoy en la zona de la cuenta' do
      ids = ids_for(due_today: true)
      expect(ids).to include(due_today_ticket.id)
      expect(ids).not_to include(due_tomorrow_ticket.id)
    end
  end

  describe 'búsqueda insensible a acentos' do
    let!(:accented) do
      create(:jabvox_ticket, account: account, requester: requester,
                             title_jabvox: 'Fallo en producción')
    end

    it 'encuentra "producción" buscando "produccion" (sin tilde)' do
      expect(ids_for(q: 'produccion')).to include(accented.id)
    end

    it 'encuentra "producción" buscando "producción" (con tilde)' do
      expect(ids_for(q: 'producción')).to include(accented.id)
    end
  end
end
