# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Platform Provisioning API', type: :request do
  let(:platform_app) { create(:platform_app) }
  let(:headers) { { api_access_token: platform_app.access_token.token } }

  describe 'POST /platform/api/v1/provisioning' do
    context 'without a valid platform token' do
      it 'responde 401' do
        post '/platform/api/v1/provisioning',
             params: { email: 'x@y.com' }, headers: { api_access_token: 'invalid' }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with a valid platform token' do
      it 'aprovisiona cuenta + admin + módulos + límites y devuelve el acceso', :aggregate_failures do
        post '/platform/api/v1/provisioning',
             params: {
               email: 'cliente@empresa.com',
               name: 'Empresa X',
               modules: %w[tickets kanban],
               limits: { inboxes: 5, agents: 10, automation_rules: 20, forms: 7 }
             },
             headers: headers, as: :json

        expect(response).to have_http_status(:created)
        body = response.parsed_body
        expect(body['account_id']).to be_present
        expect(body['admin_email']).to eq('cliente@empresa.com')
        expect(body['created_user']).to be(true)
        expect(body['modules_enabled']).to contain_exactly('tickets', 'kanban')
        expect(body['limits']['inboxes']).to eq(5)

        account = Account.find(body['account_id'])
        expect(account.jabvox_tickets_enabled_jabvox).to be(true)
        expect(account.max_forms_jabvox).to eq(7)
        # queda ligada al platform app que la creó
        expect(platform_app.platform_app_permissibles.where(permissible: account)).to exist
      end

      it 'devuelve 422 con módulo inválido' do
        post '/platform/api/v1/provisioning',
             params: { email: 'x@y.com', modules: %w[inexistente] },
             headers: headers, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to match(/desconocido/)
      end

      it 'devuelve 422 con email inválido' do
        post '/platform/api/v1/provisioning',
             params: { email: 'no-email' }, headers: headers, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
