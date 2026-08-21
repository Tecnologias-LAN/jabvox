# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Public::Plans', type: :request do
  let!(:active_plan) do
    JabvoxPlan.create!(
      slug: 'plan-basico', name: 'Plan Básico', status: :active,
      price_cents: 99_000, currency: 'COP', duration_days: 30,
      modules: %w[leads kanban], chatwoot_features: [], limits: { agents: 5 }
    )
  end

  let!(:draft_plan) do
    JabvoxPlan.create!(
      slug: 'plan-borrador', name: 'Borrador', status: :draft,
      price_cents: 50_000, currency: 'COP', duration_days: 30,
      modules: [], chatwoot_features: [], limits: {}
    )
  end

  describe 'GET /public/plans' do
    it 'retorna 200 y solo planes activos (sellable)' do
      get '/public/plans'
      expect(response).to have_http_status(:ok)
      slugs = response.parsed_body.map { |p| p['slug'] }
      expect(slugs).to include('plan-basico')
      expect(slugs).not_to include('plan-borrador')
    end

    it 'incluye precio formateado y módulos' do
      get '/public/plans'
      plan = response.parsed_body.find { |p| p['slug'] == 'plan-basico' }
      expect(plan['price_formatted']).to eq('$990.00')
      expect(plan['modules']).to contain_exactly('leads', 'kanban')
    end
  end

  describe 'GET /public/plans/:slug' do
    it 'retorna 200 para un plan activo' do
      get '/public/plans/plan-basico'
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['name']).to eq('Plan Básico')
    end

    it 'retorna 404 para un plan en borrador' do
      get '/public/plans/plan-borrador'
      expect(response).to have_http_status(:not_found)
    end

    it 'retorna 404 para un slug inexistente' do
      get '/public/plans/no-existe'
      expect(response).to have_http_status(:not_found)
    end
  end
end
