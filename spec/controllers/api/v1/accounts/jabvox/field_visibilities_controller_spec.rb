require 'rails_helper'

# update aceptaba cualquier user_id sin validar que perteneciera a la cuenta actual —
# permitía crear un JabvoxFieldVisibility(account_id: A, user_id: <de otra cuenta o
# inexistente>). No es fuga de datos ajenos (el registro vive en A), pero es un dato
# huérfano/de integridad que ahora se rechaza con 404.
RSpec.describe 'Jabvox Field Visibilities API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:member) { create(:user, account: account, role: :agent) }
  let(:other_account) { create(:account) }
  let(:outsider) { create(:user, account: other_account, role: :agent) }

  def base
    "/api/v1/accounts/#{account.id}/jabvox/field_visibilities"
  end

  describe 'PATCH /jabvox/field_visibilities' do
    it 'updates visibility for a user that belongs to the account' do
      patch base, params: { user_id: member.id, field_name: 'phone', can_view: false },
                  headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(account.jabvox_field_visibilities.find_by(user_id: member.id, field_name: 'phone').can_view).to be false
    end

    it 'rejects a user_id that does not belong to the account' do
      patch base, params: { user_id: outsider.id, field_name: 'phone', can_view: false },
                  headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(account.jabvox_field_visibilities.where(user_id: outsider.id)).to be_empty
    end

    it 'rejects a nonexistent user_id' do
      patch base, params: { user_id: 999_999_999, field_name: 'phone', can_view: false },
                  headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
