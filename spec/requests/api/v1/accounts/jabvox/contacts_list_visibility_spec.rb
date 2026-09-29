# frozen_string_literal: true

require 'rails_helper'

# El índice de esta pantalla filtra por rol, pero sus acciones no lo hacían: aceptaban
# cualquier id de la cuenta. Un agente podía así cambiar la etapa o reasignar contactos que
# la lista le oculta.
RSpec.describe 'Jabvox contacts list visibility', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:ajeno) { create(:contact, account: account, name: 'Ajeno') }

  before { account.update!(jabvox_kanban_enabled_jabvox: true) }

  def lifecycle_url(id) = "/api/v1/accounts/#{account.id}/jabvox/contacts_list/#{id}/update_lifecycle"
  def bulk_assign_url = "/api/v1/accounts/#{account.id}/jabvox/contacts_list/bulk_assign"

  describe 'PATCH update_lifecycle' do
    it 'no deja a un agente cambiar la etapa de un contacto ajeno' do
      patch lifecycle_url(ajeno.id), params: { lifecycle_stage: 'cliente' },
                                     headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(ajeno.reload.lifecycle_stage).not_to eq('cliente')
    end

    it 'deja a un agente cambiar la etapa de un contacto suyo' do
      propio = create(:contact, account: account, assignee: agent)

      patch lifecycle_url(propio.id), params: { lifecycle_stage: 'cliente' },
                                      headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end

    it 'deja a un administrador cambiar la etapa de cualquiera' do
      patch lifecycle_url(ajeno.id), params: { lifecycle_stage: 'cliente' },
                                     headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end
  end

  describe 'PATCH bulk_assign' do
    it 'no reasigna contactos que el agente no ve' do
      patch bulk_assign_url, params: { contact_ids: [ajeno.id], assignee_id: agent.id },
                             headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body['updated']).to eq(0)
      expect(ajeno.reload.assignee_id).to be_nil
    end

    it 'un administrador sí puede reasignarlos' do
      patch bulk_assign_url, params: { contact_ids: [ajeno.id], assignee_id: agent.id },
                             headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['updated']).to eq(1)
      expect(ajeno.reload.assignee_id).to eq(agent.id)
    end
  end
end
