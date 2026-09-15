require 'rails_helper'

RSpec.describe 'Webhooks::SmsController', type: :request do
  let(:account) { create(:account) }
  let!(:channel) { create(:channel_sms, phone_number: '+123221321', account: account) }
  let(:valid_token) { channel.provider_config['webhook_token'] }

  describe 'POST /webhooks/sms/{:phone_number}' do
    context 'with a valid webhook token' do
      it 'calls the sms events job with the params' do
        allow(Webhooks::SmsEventsJob).to receive(:perform_later)
        expect(Webhooks::SmsEventsJob).to receive(:perform_later)
        post '/webhooks/sms/123221321', params: { token: valid_token, content: 'hello' }
        expect(response).to have_http_status(:success)
      end
    end

    context 'without a token' do
      it 'rejects the request and never enqueues the job' do
        expect(Webhooks::SmsEventsJob).not_to receive(:perform_later)
        post '/webhooks/sms/123221321', params: { content: 'hello' }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with an invalid token' do
      it 'rejects the request and never enqueues the job' do
        expect(Webhooks::SmsEventsJob).not_to receive(:perform_later)
        post '/webhooks/sms/123221321', params: { token: 'wrong-token', content: 'hello' }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the phone number does not match any channel' do
      it 'rejects the request and never enqueues the job' do
        expect(Webhooks::SmsEventsJob).not_to receive(:perform_later)
        post '/webhooks/sms/000000000', params: { token: valid_token, content: 'hello' }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
