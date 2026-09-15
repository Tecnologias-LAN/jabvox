require 'rails_helper'

# destroy no validaba ownership: cualquier usuario con acceso al módulo Analytics podía
# borrar el export de OTRO usuario de la misma cuenta. Ahora solo el dueño del export, o
# quien tenga el permiso de gestión (jabvox_analytics_manage), puede borrarlo.
RSpec.describe 'Api::V1::Accounts::Jabvox::Analytics::Exports', type: :request do
  let(:account) { create(:account, jabvox_analytics_enabled_jabvox: true) }
  # Ambos son administradores (así pasan el check_access base de Analytics sin tener que
  # armar el sistema de roles granular del módulo); el segundo simula un admin SIN el
  # permiso de gestión de Analytics stubando jabvox_can? directamente — el foco del test es
  # el ownership check nuevo del controller, no el sistema de roles de Analytics en sí.
  let(:owner) { create(:user, account: account, role: :administrator) }
  let(:other_user) { create(:user, account: account, role: :administrator) }
  let(:dashboard) { account.jabvox_analytics_dashboards.create!(name_jabvox: 'D', created_by_id: owner.id) }
  let!(:export) do
    account.jabvox_analytics_exports.create!(dashboard: dashboard, user: owner, format_jabvox: 'pdf', params_jabvox: {})
  end

  def destroy_export(user)
    delete "/api/v1/accounts/#{account.id}/jabvox/analytics/exports/#{export.id}", headers: user.create_new_auth_token, as: :json
  end

  it 'allows the owner to delete their own export' do
    destroy_export(owner)

    expect(response).to have_http_status(:no_content)
    expect(JabvoxAnalyticsExport.exists?(export.id)).to be false
  end

  it "rejects deleting another user's export without the manage permission" do
    allow_any_instance_of(Api::V1::Accounts::Jabvox::Analytics::ExportsController) # rubocop:disable RSpec/AnyInstance
      .to receive(:jabvox_can?).and_return(false)

    destroy_export(other_user)

    expect(response).to have_http_status(:forbidden)
    expect(JabvoxAnalyticsExport.exists?(export.id)).to be true
  end
end
