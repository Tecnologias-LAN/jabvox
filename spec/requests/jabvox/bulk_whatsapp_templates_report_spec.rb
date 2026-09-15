require 'rails_helper'

RSpec.describe 'Informes → Plantillas (cross-batch WhatsApp template history)', type: :request do
  let(:account) { create(:account, jabvox_bulk_whatsapp_enabled_jabvox: true) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false) }
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:other_inbox) do
    create(:inbox, account: account, channel: create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false))
  end
  let(:contact) { create(:contact, account: account) }
  let(:ci) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: ci) }

  let(:batch_a) do
    account.jabvox_bulk_whatsapp_batches.create!(inbox: inbox, sender_user: admin, created_by: admin,
                                                 status_jabvox: 'completed', source_type_jabvox: 'jabvox', total_rows_jabvox: 1)
  end
  let(:batch_b) do
    account.jabvox_bulk_whatsapp_batches.create!(inbox: other_inbox, sender_user: admin, created_by: admin,
                                                 status_jabvox: 'completed', source_type_jabvox: 'jabvox', total_rows_jabvox: 1)
  end

  def create_recipient(batch, template_name:, sent_at:, status: 'sent')
    msg = create(:message, account: account, inbox: batch.inbox, conversation: conversation, message_type: :outgoing)
    JabvoxBulkWhatsappRecipient.create!(
      bulk_whatsapp_batch_id: batch.id, account_id: account.id, name_jabvox: 'Mel',
      phone_number_jabvox: '573001112233', template_name_jabvox: template_name,
      status_jabvox: status, chatwoot_message_id: msg.id, sent_at_jabvox: sent_at
    )
  end

  def url = "/api/v1/accounts/#{account.id}/jabvox/bulk_whatsapp/templates_report"

  it 'lists recipients across every batch, most recent send first' do
    old = create_recipient(batch_a, template_name: 'plantilla_a', sent_at: 2.days.ago)
    recent = create_recipient(batch_b, template_name: 'plantilla_b', sent_at: 1.hour.ago)

    get url, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['total']).to eq(2)
    expect(body['recipients'].map { |r| r['id'] }).to eq([recent.id, old.id])
  end

  it 'filters by template name' do
    create_recipient(batch_a, template_name: 'plantilla_a', sent_at: 1.hour.ago)
    create_recipient(batch_b, template_name: 'plantilla_b', sent_at: 1.hour.ago)

    get url, params: { template: 'plantilla_a' }, headers: admin.create_new_auth_token, as: :json

    body = response.parsed_body
    expect(body['recipients'].size).to eq(1)
    expect(body['recipients'].first['template_name']).to eq('plantilla_a')
  end

  it 'filters by inbox (joined through the batch)' do
    create_recipient(batch_a, template_name: 'plantilla_a', sent_at: 1.hour.ago)
    in_other = create_recipient(batch_b, template_name: 'plantilla_b', sent_at: 1.hour.ago)

    get url, params: { inbox_id: other_inbox.id }, headers: admin.create_new_auth_token, as: :json

    body = response.parsed_body
    expect(body['recipients'].map { |r| r['id'] }).to eq([in_other.id])
  end

  it 'filters by date range (sent_at_jabvox)' do
    within_range = create_recipient(batch_a, template_name: 'plantilla_a', sent_at: 2.days.ago)
    create_recipient(batch_a, template_name: 'plantilla_a', sent_at: 10.days.ago)

    get url, params: { from: 3.days.ago.to_i, to: 1.day.ago.to_i }, headers: admin.create_new_auth_token, as: :json

    body = response.parsed_body
    expect(body['recipients'].map { |r| r['id'] }).to eq([within_range.id])
  end

  it 'filters by status (failed)' do
    create_recipient(batch_a, template_name: 'plantilla_a', sent_at: 1.hour.ago, status: 'sent')
    failed = create_recipient(batch_a, template_name: 'plantilla_a', sent_at: 1.hour.ago, status: 'failed')

    get url, params: { status: 'failed' }, headers: admin.create_new_auth_token, as: :json

    body = response.parsed_body
    expect(body['recipients'].map { |r| r['id'] }).to eq([failed.id])
  end

  it 'searches by name/phone' do
    create_recipient(batch_a, template_name: 'plantilla_a', sent_at: 1.hour.ago)
    JabvoxBulkWhatsappRecipient.update_all(name_jabvox: 'Estrada') # rubocop:disable Rails/SkipsModelValidations -- test setup

    get url, params: { q: 'Estrada' }, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['recipients'].size).to eq(1)
  end

  it 'excludes recipients from batches that never actually sent (no sent_at_jabvox)' do
    account.jabvox_bulk_whatsapp_batches.create!(inbox: inbox, sender_user: admin, created_by: admin,
                                                 status_jabvox: 'draft', source_type_jabvox: 'jabvox', total_rows_jabvox: 1)
    JabvoxBulkWhatsappRecipient.create!(
      bulk_whatsapp_batch_id: batch_a.id, account_id: account.id, name_jabvox: 'Sin enviar',
      phone_number_jabvox: '573009998877', template_name_jabvox: 'plantilla_a', status_jabvox: 'pending', sent_at_jabvox: nil
    )

    get url, headers: admin.create_new_auth_token, as: :json

    expect(response.parsed_body['total']).to eq(0)
  end

  it 'paginates results' do
    5.times { |i| create_recipient(batch_a, template_name: 'plantilla_a', sent_at: i.hours.ago) }
    stub_const('Api::V1::Accounts::Jabvox::BulkWhatsapp::TemplatesReportController::PER_PAGE', 2)

    get url, params: { page: 2 }, headers: admin.create_new_auth_token, as: :json

    body = response.parsed_body
    expect(body['total']).to eq(5)
    expect(body['recipients'].size).to eq(2)
  end

  it 'exposes delivery_summary, distinct template names and inboxes for the filter dropdowns' do
    create_recipient(batch_a, template_name: 'plantilla_a', sent_at: 1.hour.ago)
    create_recipient(batch_b, template_name: 'plantilla_b', sent_at: 1.hour.ago)

    get url, headers: admin.create_new_auth_token, as: :json

    body = response.parsed_body
    expect(body['delivery_summary']).to include('delivered', 'read', 'replied')
    expect(body['templates']).to contain_exactly('plantilla_a', 'plantilla_b')
    expect(body['inboxes'].map { |i| i['id'] }).to contain_exactly(inbox.id, other_inbox.id)
  end

  it 'exports the same filtered scope as CSV' do
    create_recipient(batch_a, template_name: 'plantilla_a', sent_at: 1.hour.ago)

    get "#{url}.csv", headers: admin.create_new_auth_token

    expect(response).to have_http_status(:success), response.body
    expect(response.headers['Content-Type']).to include('text/csv')
    expect(response.body).to include('plantilla_a')
  end

  it 'is scoped to the current account — never leaks another account\'s recipients' do
    other_account = create(:account, jabvox_bulk_whatsapp_enabled_jabvox: true)
    other_admin = create(:user, account: other_account, role: :administrator)
    other_channel = create(:channel_whatsapp, account: other_account, sync_templates: false, validate_provider_config: false)
    other_account_inbox = create(:inbox, account: other_account, channel: other_channel)
    other_account_batch = other_account.jabvox_bulk_whatsapp_batches.create!(
      inbox: other_account_inbox, sender_user: other_admin, created_by: other_admin,
      status_jabvox: 'completed', source_type_jabvox: 'jabvox', total_rows_jabvox: 1
    )
    JabvoxBulkWhatsappRecipient.create!(
      bulk_whatsapp_batch_id: other_account_batch.id, account_id: other_account.id, name_jabvox: 'Otra cuenta',
      phone_number_jabvox: '573005554433', template_name_jabvox: 'plantilla_ajena', status_jabvox: 'sent',
      sent_at_jabvox: 1.hour.ago
    )
    create_recipient(batch_a, template_name: 'plantilla_a', sent_at: 1.hour.ago)

    get url, headers: admin.create_new_auth_token, as: :json

    body = response.parsed_body
    expect(body['total']).to eq(1)
    expect(body['recipients'].first['template_name']).to eq('plantilla_a')
  end

  it 'requires administrator/jabvox_bulk_whatsapp_send permission' do
    agent = create(:user, account: account, role: :agent)

    get url, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:forbidden)
  end
end
