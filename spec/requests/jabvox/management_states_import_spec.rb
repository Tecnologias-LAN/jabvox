# frozen_string_literal: true

require 'rails_helper'

# Full-stack request spec: exercises routing + wrap_parameters + controller so
# the import endpoint is verified exactly as the browser hits it.
RSpec.describe 'Jabvox management states import', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  let(:document) do
    {
      'version' => 1,
      'states' => [
        { 'name_jabvox' => 'Buzón de voz', 'state_group_jabvox' => 'Llamada',
          'service_type_jabvox' => 'No',
          'questions' => [
            { 'label' => 'Transferencia a SAC', 'question_type' => 'boolean' },
            { 'label' => 'Motivo SAC', 'question_type' => 'multiselect', 'options' => %w[A B],
              'visibility' => { 'logic' => 'and',
                                'rules' => [{ 'question' => 'Transferencia a SAC', 'operator' => 'equals', 'value' => 'true' }] } },
            { 'label' => 'Tel', 'question_type' => 'text', 'lead_field' => 'contact.phone_number' }
          ] }
      ]
    }
  end

  def import_url
    "/api/v1/accounts/#{account.id}/jabvox/management_states/import"
  end

  it 'imports when the document is wrapped under :data (browser shape)' do
    post import_url, params: { data: document }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(account.jabvox_management_states.count).to eq(1)
    expect(response.parsed_body['created']).to eq(1)
  end

  it 'imports when the document is posted at the root' do
    post import_url, params: document, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(account.jabvox_management_states.count).to eq(1)
  end

  it 'rejects a document with no states' do
    post import_url, params: { data: { 'version' => 1 } }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['errors'].join).to match(/states/)
  end
end
