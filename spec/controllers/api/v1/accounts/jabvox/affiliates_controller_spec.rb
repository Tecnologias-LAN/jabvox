# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Jabvox Affiliates API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  # El módulo de Afiliados se activa con una columna de la cuenta, no con un
  # feature flag de Chatwoot.
  before { account.update!(jabvox_affiliates_enabled_jabvox: true) }

  describe 'GET /api/v1/accounts/{account.id}/jabvox/affiliates' do
    it 'requires authentication' do
      get "/api/v1/accounts/#{account.id}/jabvox/affiliates"

      expect(response).to have_http_status(:unauthorized)
    end

    it 'garantiza el afiliado propio de la cuenta al listar' do
      get "/api/v1/accounts/#{account.id}/jabvox/affiliates",
          headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      owned = response.parsed_body.select { |a| a['owned'] }
      expect(owned.size).to eq(1)
    end

    it 'no crea un afiliado propio nuevo en cada consulta' do
      2.times do
        get "/api/v1/accounts/#{account.id}/jabvox/affiliates",
            headers: admin.create_new_auth_token
      end

      expect(account.jabvox_affiliates.owned.count).to eq(1)
    end

    it 'nunca devuelve afiliados de otra cuenta' do
      other = create(:account)
      create(:jabvox_affiliate, account: other, name: 'De otra cuenta')

      get "/api/v1/accounts/#{account.id}/jabvox/affiliates",
          headers: admin.create_new_auth_token

      expect(response.parsed_body.pluck('name')).not_to include('De otra cuenta')
    end
  end

  describe 'protección del afiliado propio' do
    let(:owned) { JabvoxAffiliate.owned_for!(account) }

    it 'rechaza renombrarlo por la API' do
      patch "/api/v1/accounts/#{account.id}/jabvox/affiliates/#{owned.id}",
            headers: admin.create_new_auth_token,
            params: { name: 'Hackeado' }

      expect(response).to have_http_status(:forbidden)
      expect(owned.reload.name).to eq(JabvoxAffiliate::DEFAULT_OWNED_NAME)
    end

    it 'rechaza desactivarlo por la API' do
      patch "/api/v1/accounts/#{account.id}/jabvox/affiliates/#{owned.id}",
            headers: admin.create_new_auth_token,
            params: { active: false }

      expect(response).to have_http_status(:forbidden)
      expect(owned.reload.active).to be(true)
    end

    it 'rechaza eliminarlo por la API' do
      owned # se crea antes de contar
      expect do
        delete "/api/v1/accounts/#{account.id}/jabvox/affiliates/#{owned.id}",
               headers: admin.create_new_auth_token
      end.not_to change(JabvoxAffiliate, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it 'no permite crear otro afiliado marcado como propio desde la API' do
      owned # el propio ya existe

      post "/api/v1/accounts/#{account.id}/jabvox/affiliates",
           headers: admin.create_new_auth_token,
           params: { name: 'Falso propio', owned_jabvox: true }

      # Se crea como afiliado externo normal: owned_jabvox no es asignable.
      expect(account.jabvox_affiliates.owned.count).to eq(1)
      expect(account.jabvox_affiliates.find_by(name: 'Falso propio')).not_to be_owned
    end

    it 'un afiliado externo SÍ se puede editar y eliminar' do
      external = create(:jabvox_affiliate, account: account, name: 'Externo')

      patch "/api/v1/accounts/#{account.id}/jabvox/affiliates/#{external.id}",
            headers: admin.create_new_auth_token,
            params: { name: 'Externo renombrado' }

      expect(response).to have_http_status(:success)
      expect(external.reload.name).to eq('Externo renombrado')
    end

    it 'no deja tocar el afiliado propio de OTRA cuenta' do
      other = create(:account)
      other_owned = JabvoxAffiliate.owned_for!(other)

      delete "/api/v1/accounts/#{account.id}/jabvox/affiliates/#{other_owned.id}",
             headers: admin.create_new_auth_token

      expect(response).to have_http_status(:not_found)
      expect(JabvoxAffiliate.exists?(other_owned.id)).to be(true)
    end
  end

  describe 'gating del módulo' do
    it 'rechaza cuando el módulo de afiliados está desactivado' do
      account.update!(jabvox_affiliates_enabled_jabvox: false)

      get "/api/v1/accounts/#{account.id}/jabvox/affiliates",
          headers: admin.create_new_auth_token

      expect(response).to have_http_status(:forbidden)
    end

    it 'un agente puede leer la lista pero no escribir' do
      external = create(:jabvox_affiliate, account: account)

      delete "/api/v1/accounts/#{account.id}/jabvox/affiliates/#{external.id}",
             headers: agent.create_new_auth_token

      expect(response).not_to have_http_status(:success)
      expect(JabvoxAffiliate.exists?(external.id)).to be(true)
    end
  end
end
