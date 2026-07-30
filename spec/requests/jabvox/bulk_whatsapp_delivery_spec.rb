require 'rails_helper'
RSpec.describe 'Bulk WhatsApp batch delivery status', type: :request do
  let(:account) { create(:account, jabvox_bulk_whatsapp_enabled_jabvox: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false) }
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:contact) { create(:contact, account: account) }
  let(:ci) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: ci) }
  let(:msg) { create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing) }
  let(:batch) do
    account.jabvox_bulk_whatsapp_batches.create!(inbox: inbox, sender_user: admin, created_by: admin,
      status_jabvox: 'completed', source_type_jabvox: 'jabvox', total_rows_jabvox: 1)
  end
  let!(:recipient) do
    JabvoxBulkWhatsappRecipient.create!(bulk_whatsapp_batch_id: batch.id, account_id: account.id,
      name_jabvox: 'A', phone_number_jabvox: '573001112233', status_jabvox: 'sent', chatwoot_message_id: msg.id)
  end

  before do
    MessageStatusEvent.create!(account: account, message: msg, status: :delivered, occurred_at: Time.current)
    MessageStatusEvent.create!(account: account, message: msg, status: :read, occurred_at: Time.current)
  end

  def url = "/api/v1/accounts/#{account.id}/jabvox/bulk_whatsapp/batches/#{batch.id}"

  it 'exposes delivered/read per recipient and the delivery summary', :aggregate_failures do
    get url, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['delivery_summary']).to eq('delivered' => 1, 'read' => 1)
    r = body['recipients'].first
    expect(r['delivered']).to be true
    expect(r['read']).to be true
    expect(r['chatwoot_message_id']).to eq(msg.id)
  end

  it 'filters recipients by read status' do
    get url, params: { status: 'read' }, headers: admin.create_new_auth_token, as: :json
    expect(response.parsed_body['recipients'].size).to eq(1)
  end
end
