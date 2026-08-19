# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Jabvox bulk WhatsApp batches', type: :request do
  # Enable the feature via its real column (feature_enabled? reads it).
  let(:account) { create(:account, jabvox_bulk_whatsapp_enabled_jabvox: true) }
  let!(:batch) do
    account.jabvox_bulk_whatsapp_batches.create!(
      inbox: inbox, sender_user: admin, created_by: admin,
      status_jabvox: 'running', source_type_jabvox: 'jabvox', total_rows_jabvox: 2
    )
  end
  let!(:recipient_a) do
    JabvoxBulkWhatsappRecipient.create!(bulk_whatsapp_batch_id: batch.id, account_id: account.id,
                                        name_jabvox: 'A', phone_number_jabvox: '573000000001', status_jabvox: 'pending')
  end
  let!(:recipient_b) do
    JabvoxBulkWhatsappRecipient.create!(bulk_whatsapp_batch_id: batch.id, account_id: account.id,
                                        name_jabvox: 'B', phone_number_jabvox: '573000000002', status_jabvox: 'pending')
  end
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }

  def base_url
    "/api/v1/accounts/#{account.id}/jabvox/bulk_whatsapp/batches"
  end

  describe 'GET #show' do
    it 'returns the batch with its recipients (admin only)' do
      get "#{base_url}/#{batch.id}", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['recipients'].size).to eq(2)
      expect(body['batch_uuid']).to eq(batch.batch_uuid_jabvox)
    end

    it 'filters recipients by status' do
      recipient_a.update!(status_jabvox: 'sent')
      get "#{base_url}/#{batch.id}", params: { status: 'sent' },
                                     headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['recipients'].map { |r| r['id'] }).to eq([recipient_a.id])
    end
  end

  describe 'POST #reuse' do
    before do
      recipient_a.update!(status_jabvox: 'sent', lead_id_jabvox: '11')
      recipient_b.update!(status_jabvox: 'failed', lead_id_jabvox: '22')
    end

    it 'devuelve los lead_ids de toda la audiencia + los datos del envío origen' do
      post "#{base_url}/#{batch.id}/reuse", headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['source_batch_id']).to eq(batch.id)
      expect(body['lead_ids']).to contain_exactly('11', '22')
      expect(body['lead_count']).to eq(2)
    end

    it 'filtra la audiencia por estado (solo fallidos)' do
      post "#{base_url}/#{batch.id}/reuse", params: { status: 'failed' },
                                            headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['lead_ids']).to eq(['22'])
    end

    it 'soporta estados combinados (fallidos + enviados)' do
      post "#{base_url}/#{batch.id}/reuse", params: { status: 'failed,sent' },
                                            headers: admin.create_new_auth_token, as: :json
      expect(response.parsed_body['lead_ids']).to contain_exactly('11', '22')
    end

    it 'no crea un batch nuevo (el reenvío se arma en el paso 3)' do
      expect do
        post "#{base_url}/#{batch.id}/reuse", headers: admin.create_new_auth_token, as: :json
      end.not_to change(account.jabvox_bulk_whatsapp_batches, :count)
    end
  end

  describe 'POST #results (n8n callback)' do
    def results_url
      "/api/v1/accounts/#{account.id}/jabvox/bulk_whatsapp/batches/#{batch.batch_uuid_jabvox}/results"
    end

    it 'rejects a wrong callback token' do
      post results_url,
           params: { recipient: { numero: '573000000001', status: 'sent' } },
           headers: { 'X-Jabvox-Callback-Token' => 'wrong' }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(recipient_a.reload.status_jabvox).to eq('pending')
    end

    it 'updates a recipient and recomputes the batch on a valid per-recipient callback' do
      post results_url,
           params: { recipient: { numero: '573000000001', status: 'sent', chatwoot_message_id: 99 } },
           headers: { 'X-Jabvox-Callback-Token' => batch.callback_token_jabvox }, as: :json
      expect(response).to have_http_status(:success)
      expect(recipient_a.reload.status_jabvox).to eq('sent')
      expect(recipient_a.chatwoot_message_id).to eq(99)
      # One of two reported → still running.
      expect(batch.reload.status_jabvox).to eq('running')
    end

    it 'captures the Meta error on a failed recipient' do
      post results_url,
           params: { recipient: { numero: '573000000002', status: 'failed',
                                  error_code: '131047', error_message: 'Re-engagement' } },
           headers: { 'X-Jabvox-Callback-Token' => batch.callback_token_jabvox }, as: :json
      r = recipient_b.reload
      expect(r.status_jabvox).to eq('failed')
      expect(r.error_code_jabvox).to eq('131047')
      expect(r.error_message_jabvox).to eq('Re-engagement')
    end

    it 'marks the batch final on the last-chunk summary callback' do
      recipient_a.update!(status_jabvox: 'sent')
      recipient_b.update!(status_jabvox: 'failed')
      post results_url,
           params: { summary: { total: 2, sent: 1, failed: 1, chunk_index: 0, total_chunks: 1 } },
           headers: { 'X-Jabvox-Callback-Token' => batch.callback_token_jabvox }, as: :json
      expect(response).to have_http_status(:success)
      batch.reload
      expect(batch.status_jabvox).to eq('partial')
      expect(batch.sent_count_jabvox).to eq(1)
      expect(batch.failed_count_jabvox).to eq(1)
      expect(batch.finished_at_jabvox).to be_present
    end

    it 'rejects a request with no token header' do
      post results_url, params: { recipient: { numero: '573000000001', status: 'sent' } }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(recipient_a.reload.status_jabvox).to eq('pending')
    end

    it 'returns 404 for an unknown batch uuid without leaking' do
      post "/api/v1/accounts/#{account.id}/jabvox/bulk_whatsapp/batches/#{SecureRandom.uuid}/results",
           params: { recipient: { numero: '1', status: 'sent' } },
           headers: { 'X-Jabvox-Callback-Token' => batch.callback_token_jabvox }, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'ignores unexpected/extra fields (no mass-assignment)' do
      post results_url,
           params: { recipient: { numero: '573000000001', status: 'sent',
                                  account_id: 999, status_jabvox: 'hacked', id: recipient_b.id,
                                  bulk_whatsapp_batch_id: 42, evil: '<script>' } },
           headers: { 'X-Jabvox-Callback-Token' => batch.callback_token_jabvox }, as: :json
      expect(response).to have_http_status(:success)
      recipient_a.reload
      expect(recipient_a.status_jabvox).to eq('sent')      # only the real status applied
      expect(recipient_a.account_id).to eq(account.id)     # account not reassigned
      expect(recipient_a.bulk_whatsapp_batch_id).to eq(batch.id)
    end

    it 'never touches a recipient outside the authenticated batch' do
      other_batch = account.jabvox_bulk_whatsapp_batches.create!(status_jabvox: 'running')
      outsider = JabvoxBulkWhatsappRecipient.create!(bulk_whatsapp_batch_id: other_batch.id,
                                                     account_id: account.id, phone_number_jabvox: '573000000001',
                                                     status_jabvox: 'pending')
      post results_url,
           params: { recipient: { numero: '573000000001', status: 'sent' } },
           headers: { 'X-Jabvox-Callback-Token' => batch.callback_token_jabvox }, as: :json
      expect(outsider.reload.status_jabvox).to eq('pending') # untouched: different batch
    end

    it 'truncates an oversized error message and casts ids to integers' do
      post results_url,
           params: { recipient: { numero: '573000000002', status: 'failed',
                                  error_message: 'x' * 5000, conversation_id: '55abc' } },
           headers: { 'X-Jabvox-Callback-Token' => batch.callback_token_jabvox }, as: :json
      r = recipient_b.reload
      expect(r.error_message_jabvox.length).to be <= 500
      expect(r.conversation_id).to eq(55)
    end

    it 'matches by chatwoot_message_id when provided' do
      recipient_a.update!(chatwoot_message_id: 777)
      post results_url,
           params: { recipient: { numero: 'irrelevant', chatwoot_message_id: 777, status: 'sent' } },
           headers: { 'X-Jabvox-Callback-Token' => batch.callback_token_jabvox }, as: :json
      expect(recipient_a.reload.status_jabvox).to eq('sent')
    end
  end
end
