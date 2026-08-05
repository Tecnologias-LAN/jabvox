# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Jabvox Tickets API', type: :request do
  # Cuenta gestora del helpdesk central
  let(:manager_account) { create(:account, jabvox_tickets_enabled_jabvox: true) }
  let(:staff) { create(:user, account: manager_account, role: :administrator) }

  # Cuenta cliente con módulo activo
  let(:account) { create(:account, jabvox_tickets_enabled_jabvox: true) }
  let(:owner) { create(:user, account: account, role: :agent) }
  let(:stranger) { create(:user, account: account, role: :agent) }
  # Los temas viven en la cuenta gestora (centralizados).
  let(:category) { create(:jabvox_ticket_category, account: manager_account) }

  before { create(:jabvox_ticket_helpdesk_config, account: manager_account, auto_assign_mode_jabvox: :manual) }

  def base(acc) = "/api/v1/accounts/#{acc.id}/jabvox/tickets/tickets"

  describe 'POST create' do
    it 'un usuario registra un ticket a su nombre' do
      post base(account),
           params: { title_jabvox: 'No imprime', description_jabvox: 'error', ticket_category_id: category.id,
                     priority_jabvox: 'high' },
           headers: owner.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body['title']).to eq('No imprime')
      expect(body['requester']['id']).to eq(owner.id)
      expect(body['display_id']).to eq(1)
    end
  end

  describe 'GET index (aislamiento por permisos)' do
    let!(:own_ticket) { create(:jabvox_ticket, account: account, requester: owner) }
    let!(:other_ticket) { create(:jabvox_ticket, account: account, requester: stranger) }

    it 'el requester ve SOLO sus tickets' do
      get base(account), headers: owner.create_new_auth_token, as: :json
      ids = response.parsed_body['data'].map { |t| t['id'] }
      expect(ids).to contain_exactly(own_ticket.id)
      expect(ids).not_to include(other_ticket.id)
    end

    it 'el staff de la cuenta gestora ve TODOS los tickets' do
      get base(manager_account), headers: staff.create_new_auth_token, as: :json
      ids = response.parsed_body['data'].map { |t| t['id'] }
      expect(ids).to include(own_ticket.id, other_ticket.id)
    end
  end

  describe 'seguridad: acceso directo a un ticket ajeno' do
    let(:other_ticket) { create(:jabvox_ticket, account: account, requester: stranger) }

    it 'un requester recibe 403 al ver un ticket que no es suyo' do
      get "#{base(account)}/#{other_ticket.id}", headers: owner.create_new_auth_token, as: :json
      expect(response.status).to be_in([401, 403, 404])
    end

    it 'un requester no puede resolver un ticket ajeno' do
      post "#{base(account)}/#{other_ticket.id}/resolve",
           params: { resolution: 'x', resolution_type: 'solved' },
           headers: owner.create_new_auth_token, as: :json
      expect(response.status).to be_in([401, 403, 404])
    end
  end

  describe 'ciclo de vida (staff)' do
    let(:ticket) { create(:jabvox_ticket, account: account, requester: owner) }

    it 'staff resuelve (desde su cuenta gestora) y el solicitante califica' do
      # El staff opera a través de SU cuenta gestora (el ticket puede ser de otra cuenta).
      post "#{base(manager_account)}/#{ticket.id}/resolve",
           params: { resolution: 'reiniciado', resolution_type: 'solved' },
           headers: staff.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(ticket.reload.status_jabvox).to eq('resolved')

      post "#{base(account)}/#{ticket.id}/rate",
           params: { rating: 5, comment: 'excelente' },
           headers: owner.create_new_auth_token, as: :json
      expect(response).to have_http_status(:ok)
      expect(ticket.reload.satisfaction_rating_jabvox).to eq(5)
    end
  end

  describe 'feature flag' do
    let(:no_module) { create(:account) }
    let(:user) { create(:user, account: no_module, role: :agent) }

    it 'devuelve 403 si el módulo no está activo' do
      get base(no_module), headers: user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end
end
