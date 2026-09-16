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

  def bulk_id(recipient) = "bulk-#{recipient.id}"

  it 'lists recipients across every batch, most recent send first' do
    old = create_recipient(batch_a, template_name: 'plantilla_a', sent_at: 2.days.ago)
    recent = create_recipient(batch_b, template_name: 'plantilla_b', sent_at: 1.hour.ago)

    get url, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['total']).to eq(2)
    expect(body['recipients'].map { |r| r['id'] }).to eq([bulk_id(recent), bulk_id(old)])
    expect(body['recipients'].map { |r| r['origin'] }).to all(eq('bulk'))
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
    expect(body['recipients'].map { |r| r['id'] }).to eq([bulk_id(in_other)])
  end

  it 'filters by date range (sent_at_jabvox)' do
    within_range = create_recipient(batch_a, template_name: 'plantilla_a', sent_at: 2.days.ago)
    create_recipient(batch_a, template_name: 'plantilla_a', sent_at: 10.days.ago)

    get url, params: { from: 3.days.ago.to_i, to: 1.day.ago.to_i }, headers: admin.create_new_auth_token, as: :json

    body = response.parsed_body
    expect(body['recipients'].map { |r| r['id'] }).to eq([bulk_id(within_range)])
  end

  it 'filters by status (failed)' do
    create_recipient(batch_a, template_name: 'plantilla_a', sent_at: 1.hour.ago, status: 'sent')
    failed = create_recipient(batch_a, template_name: 'plantilla_a', sent_at: 1.hour.ago, status: 'failed')

    get url, params: { status: 'failed' }, headers: admin.create_new_auth_token, as: :json

    body = response.parsed_body
    expect(body['recipients'].map { |r| r['id'] }).to eq([bulk_id(failed)])
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
    # Every WhatsApp inbox of the account, not just the ones a bulk batch used —
    # an individual template send can come from any of them.
    expect(body['inboxes'].map { |i| i['id'] }).to include(inbox.id, other_inbox.id)
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

  # An agent sending a template 1-a-1 from the conversation composer never goes
  # through JabvoxBulkWhatsappRecipient — it's a plain Message with
  # additional_attributes.template_params (see Messages::MessageBuilder). This
  # report has to surface those too, alongside bulk sends, or "every template
  # ever sent, from anywhere" would silently miss half its own sends.
  def create_individual_template_message(template_name:, created_at:, status: 'sent')
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :template,
                     status: status, created_at: created_at,
                     additional_attributes: { template_params: { name: template_name, category: 'MARKETING', language: 'es' } })
  end

  describe 'individual (1-a-1) template sends' do
    it 'includes a template sent from the conversation composer, not just bulk sends' do
      msg = create_individual_template_message(template_name: 'seguimiento_propuesta', created_at: 1.hour.ago)

      get url, headers: admin.create_new_auth_token, as: :json

      body = response.parsed_body
      expect(body['total']).to eq(1)
      row = body['recipients'].first
      expect(row['id']).to eq("msg-#{msg.id}")
      expect(row['origin']).to eq('individual')
      expect(row['template_name']).to eq('seguimiento_propuesta')
      expect(row['name']).to eq(contact.name)
      expect(row['phone_number']).to eq(contact.phone_number)
    end

    it 'shows every template sent to the same lead, from every origin, without deduplicating by contact' do
      # Exactly the scenario the report exists for: one lead (same phone/contact),
      # 3 different template sends via 3 different paths — all 3 must show up,
      # never collapsed into one row just because it's the same person.
      create_recipient(batch_a, template_name: 'formulario_de_intencion', sent_at: 3.hours.ago)
      create_individual_template_message(template_name: 'seguimiento_propuesta', created_at: 2.hours.ago)
      create_individual_template_message(template_name: 'otra_plantilla', created_at: 1.hour.ago)

      get url, headers: admin.create_new_auth_token, as: :json

      body = response.parsed_body
      expect(body['total']).to eq(3)
      expect(body['recipients'].map { |r| r['template_name'] })
        .to eq(%w[otra_plantilla seguimiento_propuesta formulario_de_intencion])
    end

    it 'a failed individual send is reported as failed, with its Meta error' do
      create_individual_template_message(template_name: 'plantilla_x', created_at: 1.hour.ago, status: 'failed')
      Message.last.update_column(:content_attributes, { external_error: '131009: Parameter value is not valid' }) # rubocop:disable Rails/SkipsModelValidations -- test setup only

      get url, headers: admin.create_new_auth_token, as: :json

      row = response.parsed_body['recipients'].first
      expect(row['status']).to eq('failed')
      expect(row['error_message']).to eq('131009: Parameter value is not valid')
    end

    it 'filters individual sends by template name alongside bulk ones' do
      create_recipient(batch_a, template_name: 'plantilla_a', sent_at: 1.hour.ago)
      create_individual_template_message(template_name: 'plantilla_b', created_at: 1.hour.ago)

      get url, params: { template: 'plantilla_b' }, headers: admin.create_new_auth_token, as: :json

      body = response.parsed_body
      expect(body['recipients'].size).to eq(1)
      expect(body['recipients'].first['origin']).to eq('individual')
    end

    it 'lists individual template names in the template filter dropdown too' do
      create_individual_template_message(template_name: 'solo_individual', created_at: 1.hour.ago)

      get url, headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['templates']).to include('solo_individual')
    end

    it 'includes a "Vía de envío" column in the CSV distinguishing bulk from individual' do
      create_recipient(batch_a, template_name: 'plantilla_a', sent_at: 1.hour.ago)
      create_individual_template_message(template_name: 'plantilla_b', created_at: 1.hour.ago)

      get "#{url}.csv", headers: admin.create_new_auth_token

      expect(response.body).to include('Vía de envío')
      expect(response.body).to include('Masivo')
      expect(response.body).to include('Individual')
    end
  end
end
