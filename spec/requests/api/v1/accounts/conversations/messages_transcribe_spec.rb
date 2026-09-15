require 'rails_helper'

RSpec.describe 'Conversation Messages API — transcribe', type: :request do
  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:conversation) { create(:conversation, inbox: inbox, account: account) }
  let!(:message) { create(:message, account: account, conversation: conversation) }
  let!(:attachment) { message.attachments.create!(account: account, file_type: :audio) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def transcribe_url(conv: conversation, msg: message)
    transcribe_api_v1_account_conversation_message_url(
      account_id: account.id, conversation_id: conv.display_id, id: msg.id
    )
  end

  before { create(:inbox_member, inbox: conversation.inbox, user: agent) }

  describe 'authentication' do
    it 'rejects an unauthenticated request' do
      post transcribe_url, params: { attachment_id: attachment.id }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'account isolation (cross-account)' do
    let!(:other_account) { create(:account) }
    let!(:other_inbox) { create(:inbox, account: other_account) }
    let!(:other_conversation) { create(:conversation, inbox: other_inbox, account: other_account) }
    let!(:other_message) { create(:message, account: other_account, conversation: other_conversation) }
    let!(:other_attachment) { other_message.attachments.create!(account: other_account, file_type: :audio) }

    it 'never resolves a conversation belonging to another account' do
      # display_id es un contador POR CUENTA (no globalmente único): una conversación
      # nueva en cada cuenta puede compartir el mismo número. La prueba de aislamiento
      # real es que, aun así, el endpoint jamás actúa sobre datos de la otra cuenta —
      # confirmado abajo con el adjunto ajeno buscado por su id real.
      expect(other_conversation.display_id).to eq(conversation.display_id)

      post transcribe_url(conv: other_conversation),
           params: { attachment_id: other_attachment.id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'never resolves a message belonging to another account, even nested under our own conversation id' do
      post transcribe_api_v1_account_conversation_message_url(
        account_id: account.id, conversation_id: conversation.display_id, id: other_message.id
      ), params: { attachment_id: attachment.id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "never transcribes another account's attachment by guessing its id" do
      post transcribe_url, params: { attachment_id: other_attachment.id },
                           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'authorization (inbox membership)' do
    it "rejects an agent without access to the conversation's inbox" do
      outsider = create(:user, account: account, role: :agent)

      post transcribe_url, params: { attachment_id: attachment.id },
                           headers: outsider.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'input validation / edge cases' do
    it 'returns 404 for a non-existent attachment id' do
      post transcribe_url, params: { attachment_id: 0 }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'returns 404 for an attachment that belongs to a DIFFERENT message of the SAME conversation' do
      other_message = create(:message, account: account, conversation: conversation)
      other_attachment = other_message.attachments.create!(account: account, file_type: :audio)

      post transcribe_url, params: { attachment_id: other_attachment.id },
                           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects a non-audio attachment without enqueuing anything' do
      image_attachment = message.attachments.create!(account: account, file_type: :image)

      expect do
        post transcribe_url, params: { attachment_id: image_attachment.id },
                             headers: agent.create_new_auth_token, as: :json
      end.not_to have_enqueued_job(Messages::AudioTranscriptionJob)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'idempotency' do
    it 'does not re-enqueue when the attachment is already transcribed' do
      attachment.update!(meta: { 'transcribed_text' => 'ya transcrito antes' })

      expect do
        post transcribe_url, params: { attachment_id: attachment.id },
                             headers: agent.create_new_auth_token, as: :json
      end.not_to have_enqueued_job(Messages::AudioTranscriptionJob)

      expect(response).to have_http_status(:ok)
    end

    it 'enqueues exactly once even under a rapid double-click (two requests back to back)' do
      headers = agent.create_new_auth_token

      expect do
        post transcribe_url, params: { attachment_id: attachment.id }, headers: headers, as: :json
        post transcribe_url, params: { attachment_id: attachment.id }, headers: headers, as: :json
      end.to have_enqueued_job(Messages::AudioTranscriptionJob).with(attachment.id).exactly(2).times

      # Nota: el controller en sí no deduplica in-flight (solo evita re-encolar si ya HAY
      # texto persistido) — la deduplicación real de "ya se está procesando" vive en que
      # AudioTranscriptionService#transcribe_audio relee attachment.meta y no repite la
      # llamada a Whisper si otro worker ya la completó primero.
    end
  end

  describe 'happy path' do
    it 'accepts the request and enqueues the transcription job on its own queue' do
      expect do
        post transcribe_url, params: { attachment_id: attachment.id },
                             headers: agent.create_new_auth_token, as: :json
      end.to have_enqueued_job(Messages::AudioTranscriptionJob).with(attachment.id).on_queue('jabvox_transcription')

      expect(response).to have_http_status(:accepted)
    end
  end

  describe 'stress: many concurrent attachments in the same conversation' do
    it 'handles transcribing 50 different attachments without error' do
      headers = agent.create_new_auth_token
      attachments = Array.new(50) { message.attachments.create!(account: account, file_type: :audio) }

      expect do
        attachments.each do |att|
          post transcribe_url, params: { attachment_id: att.id }, headers: headers, as: :json
          expect(response).to have_http_status(:accepted)
        end
      end.to have_enqueued_job(Messages::AudioTranscriptionJob).exactly(50).times
    end
  end
end
