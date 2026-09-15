require 'rails_helper'

RSpec.describe 'Hermes Tasks API', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:headers) { user.create_new_auth_token }

  # Regresión: tras unificar Captain en Hermes (commit 1226a19eb), este controller quedó
  # llamando authorize(:'captain/tasks') — un símbolo que Pundit resuelve a la constante
  # Captain::TasksPolicy, ya eliminada. Cualquier acción del menú de IA de la conversación
  # (mejorar redacción, cambiar tono, corregir ortografía, resumir, sugerir respuesta)
  # lanzaba NameError: uninitialized constant Captain y devolvía 500.
  it 'authorizes against Hermes::TasksPolicy, not a stale Captain:: constant' do
    service = instance_double(Hermes::RewriteService, perform: { message: 'texto mejorado' })
    allow(Hermes::RewriteService).to receive(:new).and_return(service)

    post "/api/v1/accounts/#{account.id}/hermes/tasks/rewrite",
         params: { content: 'hola', operation: 'improve' }, headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['message']).to eq('texto mejorado')
  end

  it 'surfaces a service error as 422 instead of a 500' do
    service = instance_double(Hermes::RewriteService, perform: { error: 'sin api key' })
    allow(Hermes::RewriteService).to receive(:new).and_return(service)

    post "/api/v1/accounts/#{account.id}/hermes/tasks/rewrite",
         params: { content: 'hola', operation: 'improve' }, headers: headers, as: :json

    expect(response).to have_http_status(:unprocessable_content)
  end
end
