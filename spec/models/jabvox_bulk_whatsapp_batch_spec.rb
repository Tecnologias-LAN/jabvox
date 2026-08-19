# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JabvoxBulkWhatsappBatch do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  # El token del envío se revoca cuando el batch llega a estado terminal (lo confirma n8n).
  describe '#recalculate_status! token revocation' do
    let(:token) { AccessToken.create!(owner: user, expires_at: nil) }
    let(:batch) do
      described_class.create!(account: account, sender_user: user, status_jabvox: 'running',
                              access_token_id_jabvox: token.id, payload_jabvox: {})
    end

    it 'revoca el token al completar (todos enviados)' do
      add_recipient(batch, 'sent')
      batch.recalculate_status!
      expect(batch.reload.status_jabvox).to eq('completed')
      expect(AccessToken.exists?(token.id)).to be(false)
      expect(batch.access_token_id_jabvox).to be_nil
    end

    it 'NO revoca el token mientras siga en running (aún procesando)' do
      add_recipient(batch, 'sent')
      add_recipient(batch, 'pending')
      batch.recalculate_status!
      expect(batch.reload.status_jabvox).to eq('running')
      expect(AccessToken.exists?(token.id)).to be(true)
    end

    it 'revoca el token en estado partial (hubo fallidos)' do
      add_recipient(batch, 'sent')
      add_recipient(batch, 'failed')
      batch.recalculate_status!
      expect(batch.reload.status_jabvox).to eq('partial')
      expect(AccessToken.exists?(token.id)).to be(false)
    end

    def add_recipient(batch, status)
      JabvoxBulkWhatsappRecipient.create!(
        batch: batch, account: account, phone_number_jabvox: '573000000000',
        status_jabvox: status
      )
    end
  end
end
