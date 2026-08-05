# frozen_string_literal: true

require 'rails_helper'

# Temas/categorías centralizados en la cuenta gestora: toda cuenta cliente los LEE
# de la gestora; solo el staff de la gestora los crea/edita; y un ticket solo puede
# usar una categoría de la gestora.
RSpec.describe 'Jabvox Tickets categories (centralizadas)', type: :request do
  let(:manager_account) { create(:account, jabvox_tickets_enabled_jabvox: true) }
  let(:staff) { create(:user, account: manager_account, role: :administrator) }
  let(:client_account) { create(:account, jabvox_tickets_enabled_jabvox: true) }
  let(:client_user) { create(:user, account: client_account, role: :agent) }

  before { create(:jabvox_ticket_helpdesk_config, account: manager_account, auto_assign_mode_jabvox: :manual) }

  def categories_url(acc) = "/api/v1/accounts/#{acc.id}/jabvox/tickets/categories"
  def tickets_url(acc) = "/api/v1/accounts/#{acc.id}/jabvox/tickets/tickets"

  describe 'GET index' do
    # rubocop:disable RSpec/LetSetup -- ambos se consultan vía la API, no directamente
    let!(:manager_topic) { create(:jabvox_ticket_category, account: manager_account, name_jabvox: 'Falla técnica') }
    let!(:client_topic) { create(:jabvox_ticket_category, account: client_account, name_jabvox: 'Local del cliente') }
    # rubocop:enable RSpec/LetSetup

    it 'una cuenta cliente ve los temas de la GESTORA, no los suyos' do
      get categories_url(client_account), headers: client_user.create_new_auth_token, as: :json
      names = response.parsed_body['data'].map { |c| c['name'] }
      expect(names).to include('Falla técnica')
      expect(names).not_to include('Local del cliente')
    end
  end

  describe 'POST create' do
    it 'el staff de la gestora crea el tema EN la cuenta gestora' do
      post categories_url(manager_account),
           params: { name_jabvox: 'Nuevo tema', category_type_jabvox: 'incident' },
           headers: staff.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)
      expect(manager_account.jabvox_ticket_categories.find_by(name_jabvox: 'Nuevo tema')).to be_present
    end

    it 'un usuario de cuenta cliente NO puede crear temas' do
      post categories_url(client_account),
           params: { name_jabvox: 'Intruso', category_type_jabvox: 'incident' },
           headers: client_user.create_new_auth_token, as: :json
      expect(response.status).to be_in([401, 403])
      expect(JabvoxTicketCategory.find_by(name_jabvox: 'Intruso')).to be_nil
    end
  end

  describe 'seguridad al crear ticket con categoría' do
    let(:manager_topic) { create(:jabvox_ticket_category, account: manager_account) }
    let(:foreign_topic) { create(:jabvox_ticket_category, account: client_account) }

    it 'acepta una categoría de la cuenta gestora' do
      post tickets_url(client_account),
           params: { title_jabvox: 'Con tema válido', ticket_category_id: manager_topic.id },
           headers: client_user.create_new_auth_token, as: :json
      expect(response).to have_http_status(:created)
    end

    it 'rechaza una categoría que NO es de la gestora (inyección)' do
      post tickets_url(client_account),
           params: { title_jabvox: 'Con tema ajeno', ticket_category_id: foreign_topic.id },
           headers: client_user.create_new_auth_token, as: :json
      expect(response.status).to be_in([422, 400, 404])
      expect(JabvoxTicket.find_by(title_jabvox: 'Con tema ajeno')).to be_nil
    end
  end
end
