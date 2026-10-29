# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jabvox::Drive::MediaIngestJob do
  let(:account) { create(:account) }
  let(:operation) do
    JabvoxDrivePendingOperation.enqueue(
      account: account, kind: 'ingest_media', idempotency_key: 'wa-media-1-abc',
      payload: { provider: 'whatsapp_cloud', media_id: 'abc', filename: 'foto.jpg',
                 content_type: 'image/jpeg', message_id: 1, inbox_id: 1 }
    )
  end

  describe 'resiliencia ante caída de MinIO' do
    it 'deja la operación pendiente sin perder el trabajo' do
      allow_any_instance_of(Jabvox::Drive::StorageService).to receive(:available?).and_return(false)

      expect { described_class.perform_now(account.id, operation.id) }.not_to raise_error

      operation.reload
      expect(operation).to be_pending            # NO se pierde
      expect(operation.attempts).to eq(1)        # se registró un intento
      expect(operation.last_error).to match(/MinIO/i)
      expect(operation.next_attempt_at).to be_present # reintento agendado
    end
  end

  describe 'idempotencia' do
    it 'no hace nada si la operación ya está completada' do
      operation.mark_completed!
      expect_any_instance_of(Jabvox::Drive::StorageService).not_to receive(:available?)
      described_class.perform_now(account.id, operation.id)
      expect(operation.reload).to be_completed
    end

    it 'ignora cuenta u operación inexistentes sin fallar' do
      expect { described_class.perform_now(-1, -1) }.not_to raise_error
      expect { described_class.perform_now(account.id, -1) }.not_to raise_error
    end
  end

  describe 'error permanente' do
    it 'marca failed cuando falta media_id' do
      operation.update!(payload: { provider: 'whatsapp_cloud' })
      described_class.perform_now(account.id, operation.id)
      expect(operation.reload).to be_failed
      expect(operation.last_error).to match(/media_id/)
    end
  end
end
