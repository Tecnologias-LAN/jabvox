# frozen_string_literal: true

require 'rails_helper'

# Regresión del bug "No se pudo guardar la gestión": typify devolvía 404 cuando el
# contact_id (campaign_contact) aún no tenía call log, y la tipificación se perdía.
# Ahora crea el log si falta, para que la gestión siempre se guarde.
RSpec.describe 'Api::V1::Accounts::Jabvox::DialerCallLogs typify', type: :request do
  let(:account) { create(:account, jabvox_dialer_enabled_jabvox: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:campaign) do
    JabvoxDialerCampaign.create!(account_id: account.id, name_jabvox: 'C', status_jabvox: 'active',
                                 dial_mode_jabvox: 'one_by_one')
  end
  let(:contact) { create(:contact, account: account) }
  let(:cc) do
    JabvoxDialerCampaignContact.create!(account_id: account.id, jabvox_dialer_campaign_id: campaign.id,
                                        contact_id: contact.id, phone_jabvox: '3001112233', status_jabvox: 'no_answer')
  end
  let(:typification) do
    JabvoxTypification.create!(account_id: account.id, name: 'Contestó')
  end

  def typify(body)
    patch "/api/v1/accounts/#{account.id}/jabvox/dialer_call_logs/typify",
          params: body, headers: admin.create_new_auth_token, as: :json
  end

  it 'crea el call log y guarda la tipificación cuando el contacto no tenía log' do
    expect(account.jabvox_dialer_call_logs.where(jabvox_dialer_campaign_contact_id: cc.id)).to be_empty

    typify(contact_id: cc.id, typification_id: typification.id, notes_jabvox: 'gestión')

    expect(response).to have_http_status(:ok)
    log = account.jabvox_dialer_call_logs.find_by(jabvox_dialer_campaign_contact_id: cc.id)
    expect(log).to be_present
    expect(log.typification_id).to eq(typification.id)
    expect(log.notes_jabvox).to eq('gestión')
  end

  it 'actualiza el log existente en vez de crear otro' do
    existing = JabvoxDialerCallLog.create!(
      account_id: account.id, jabvox_dialer_campaign_id: campaign.id,
      jabvox_dialer_campaign_contact_id: cc.id, phone_jabvox: '3001112233',
      status_jabvox: 'no_answer', agent_id_jabvox: admin.id, started_at_jabvox: Time.current
    )

    expect { typify(contact_id: cc.id, typification_id: typification.id) }
      .not_to change { account.jabvox_dialer_call_logs.count }
    expect(existing.reload.typification_id).to eq(typification.id)
  end
end
