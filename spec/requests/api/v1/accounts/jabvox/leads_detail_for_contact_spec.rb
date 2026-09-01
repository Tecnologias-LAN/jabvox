# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Jabvox lead detail for contact', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) do
    create(:contact, account: account, name: 'Estrada', phone_number: '+573233653776',
                     additional_attributes: { 'jabvox_identification_number' => 'CC123',
                                              'jabvox_contact_type' => 'persona', 'country' => 'Colombia' })
  end

  def url(contact_id) = "/api/v1/accounts/#{account.id}/jabvox/leads/detail_for_contact/#{contact_id}"

  before do
    account.update!(jabvox_leads_enabled_jabvox: true)
    lead = JabvoxLead.find_or_create_by!(account: account, contact: contact) do |l|
      l.lead_number = (account.jabvox_leads.maximum(:lead_number) || 0) + 1
    end
    lead.update!(assignee: agent)
  end

  it 'returns the full lead detail for a contact' do
    get url(contact.id), headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['contact']['name']).to eq('Estrada')
    expect(body['contact']['identification']).to eq('CC123')
    expect(body['contact']['contact_type']).to eq('persona')
    expect(body['contact']['country']).to eq('Colombia')
    expect(body['lead']['assignee_name']).to eq(agent.name)
    expect(body).to have_key('custom_fields')
  end

  it 'is available to a plain agent (not gated by the reports permission)' do
    get url(contact.id), headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
  end

  it 'returns 404 for a contact without data' do
    get url(0), headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
  end
end
