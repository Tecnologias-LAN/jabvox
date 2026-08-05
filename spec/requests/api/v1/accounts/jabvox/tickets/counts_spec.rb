# frozen_string_literal: true

require 'rails_helper'

# Endpoint de conteos del badge: pendientes de hoy (verde) y vencidas de días
# anteriores (rojo), respetando el scope de permisos.
RSpec.describe 'Jabvox Tickets counts', type: :request do
  let(:manager_account) { create(:account, jabvox_tickets_enabled_jabvox: true) }
  let(:staff) { create(:user, account: manager_account, role: :administrator) }
  let(:client_account) { create(:account, jabvox_tickets_enabled_jabvox: true) }
  let(:requester) { create(:user, account: client_account, role: :agent) }

  before do
    create(:jabvox_ticket_helpdesk_config, account: manager_account,
                                           business_hours_jabvox: { 'time_zone' => 'America/Bogota' })
  end

  # Cada quien consulta el badge desde SU cuenta (el scope de la policy filtra).
  def counts_url(acc) = "/api/v1/accounts/#{acc.id}/jabvox/tickets/counts"

  def body_for(user, acc)
    get counts_url(acc), headers: user.create_new_auth_token, as: :json
    response.parsed_body
  end

  it 'cuenta las pendientes creadas hoy (staff ve todo)' do
    create(:jabvox_ticket, account: client_account, requester: requester)
    expect(body_for(staff, manager_account)['today']).to eq(1)
  end

  it 'cuenta las vencidas de días anteriores' do
    old = create(:jabvox_ticket, account: client_account, requester: requester)
    old.update_columns( # rubocop:disable Rails/SkipsModelValidations
      created_at: 3.days.ago, due_at_jabvox: 2.days.ago
    )
    body = body_for(staff, manager_account)
    expect(body['overdue_previous']).to eq(1)
    expect(body['today']).to eq(0)
  end

  it 'respeta el scope: un requester solo cuenta lo suyo' do
    other = create(:user, account: client_account, role: :agent)
    create(:jabvox_ticket, account: client_account, requester: other) # ajeno
    create(:jabvox_ticket, account: client_account, requester: requester) # propio
    body = body_for(requester, client_account)
    expect(body['today']).to eq(1) # solo el suyo, no el ajeno
  end
end
