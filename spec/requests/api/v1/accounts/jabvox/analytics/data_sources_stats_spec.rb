# frozen_string_literal: true

require 'rails_helper'

# Conteo de tablas y vistas que se muestra junto a "Ver tablas".
#
# Devolvía 422 siempre: `stats` no estaba en el `before_action :set_data_source`, así que
# `@data_source` llegaba nil y SchemaStats reventaba con NoMethodError, que el rescue del
# controlador traducía al mensaje genérico. Tampoco estaba en el before_action de
# autorización, así que no comprobaba el acceso a esa fuente concreta.
RSpec.describe 'Jabvox Analytics data source stats', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  let(:data_source) do
    cfg = ActiveRecord::Base.connection_db_config.configuration_hash
    account.jabvox_analytics_data_sources.create!(
      name_jabvox: 'Fuente de prueba', engine_jabvox: 'postgresql',
      host_jabvox: cfg[:host] || '127.0.0.1', port_jabvox: cfg[:port] || 5432,
      database_jabvox: cfg[:database], username_jabvox: cfg[:username].to_s,
      password_jabvox: cfg[:password].to_s, status_jabvox: 'ok'
    )
  end

  before { account.update!(jabvox_analytics_enabled_jabvox: true) }

  def stats_url(id) = "/api/v1/accounts/#{account.id}/jabvox/analytics/data_sources/#{id}/stats"

  it 'devuelve el conteo de tablas y vistas' do
    get stats_url(data_source.id), headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['total']).to eq(body['tables'] + body['views'])
    expect(body['total']).to be_positive
  end

  it 'devuelve 404 para una fuente que no existe en la cuenta' do
    get stats_url(0), headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end

  it 'no expone la fuente de otra cuenta' do
    ajena = create(:account)
    otra_fuente = ajena.jabvox_analytics_data_sources.create!(
      name_jabvox: 'Ajena', engine_jabvox: 'postgresql', host_jabvox: '127.0.0.1',
      port_jabvox: 5432, database_jabvox: 'x', username_jabvox: 'x', status_jabvox: 'ok'
    )

    get stats_url(otra_fuente.id), headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end
end
