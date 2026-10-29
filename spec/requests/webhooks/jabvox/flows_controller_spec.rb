# frozen_string_literal: true

require 'rails_helper'

# Verifica de punta a punta el disparador "Webhook entrante" (trigger.webhook):
# resolución por token, gate de feature, matcheo del nodo, secreto y encolado del
# run con el payload accesible como {{trigger.*}}.
RSpec.describe 'Webhooks::Jabvox::Flows', type: :request do
  let(:account) { create(:account) }

  def crear_flujo(webhook_params: { 'allowedMethods' => ['POST'] }, feature: true)
    # El módulo "Avanzadas" se gatea por una COLUMNA propia, no por enabled_features.
    account.update!(jabvox_advanced_automations_enabled_jabvox: feature)
    flow = account.jabvox_flows.create!(name: 'WH', status: :active)
    graph = { 'nodes' => [{ 'id' => 'wh', 'data' => { 'nodeType' => 'trigger.webhook', 'params' => webhook_params } }],
              'edges' => [] }
    version = flow.versions.create!(version: 1, graph: graph)
    flow.update!(current_version: version)
    flow
  end

  it 'encola un run y deja el body accesible como {{trigger.body}}' do
    flow = crear_flujo

    expect do
      post "/webhooks/jabvox/flows/#{flow.webhook_token}", params: { email: 'a@b.co' }
    end.to change { flow.runs.count }.by(1)

    expect(response).to have_http_status(:accepted)
    run = flow.runs.last
    expect(run.trigger['type']).to eq('trigger.webhook')
    expect(run.trigger['body']).to include('email' => 'a@b.co')
  end

  it 'responde 404 si el token no existe' do
    post '/webhooks/jabvox/flows/token-inexistente'
    expect(response).to have_http_status(:not_found)
  end

  it 'responde 403 si el módulo no está activo' do
    flow = crear_flujo(feature: false)
    post "/webhooks/jabvox/flows/#{flow.webhook_token}"
    expect(response).to have_http_status(:forbidden)
  end

  it 'rechaza un método no permitido por el nodo' do
    flow = crear_flujo(webhook_params: { 'allowedMethods' => ['POST'] })
    get "/webhooks/jabvox/flows/#{flow.webhook_token}"
    expect(response).to have_http_status(:forbidden)
  end

  it 'exige el secreto cuando el nodo lo configura' do
    flow = crear_flujo(webhook_params: { 'allowedMethods' => ['POST'], 'secret' => 's3cr3t' })

    post "/webhooks/jabvox/flows/#{flow.webhook_token}"
    expect(response).to have_http_status(:forbidden)

    expect do
      post "/webhooks/jabvox/flows/#{flow.webhook_token}", headers: { 'X-Jabvox-Flow-Secret' => 's3cr3t' }
    end.to change { flow.runs.count }.by(1)
    expect(response).to have_http_status(:accepted)
  end
end
