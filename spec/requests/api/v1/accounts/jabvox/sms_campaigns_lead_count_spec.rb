# frozen_string_literal: true

require 'rails_helper'

# Conteo previo al envío de una campaña de SMS.
#
# Devolvía 500: el filtrado ya trabajaba sobre contactos, pero el conteo de "con teléfono"
# seguía haciendo `joins(:contact)`, herencia de cuando filtraba leads y cada lead colgaba
# de un contacto. Un contacto no tiene asociación `contact`, así que la consulta reventaba.
RSpec.describe 'Jabvox SMS campaigns lead_count', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }

  let(:url) { "/api/v1/accounts/#{account.id}/jabvox/sms_campaigns/lead_count" }

  before { account.update!(jabvox_sms_enabled_jabvox: true) }

  def get_count(params = {})
    get url, params: params, headers: admin.create_new_auth_token, as: :json
    response.parsed_body
  end

  it 'cuenta los contactos y distingue los que tienen teléfono' do
    create(:contact, account: account, phone_number: '+573001112233')
    create(:contact, account: account, phone_number: nil)

    body = get_count

    expect(response).to have_http_status(:success)
    expect(body['total_count']).to eq(2)
    expect(body['with_phone_count']).to eq(1)
  end

  it 'filtra por bandeja sin romperse' do
    con_conversacion = create(:contact, account: account, phone_number: '+573001112233')
    create(:conversation, account: account, inbox: inbox, contact: con_conversacion)
    create(:contact, account: account, phone_number: '+573004445566')

    body = get_count(inbox_ids: [inbox.id])

    expect(response).to have_http_status(:success)
    expect(body['total_count']).to eq(1)
    expect(body['with_phone_count']).to eq(1)
  end
end
