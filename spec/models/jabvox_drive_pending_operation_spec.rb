# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JabvoxDrivePendingOperation do
  let(:account) { create(:account) }

  describe '.enqueue (idempotencia)' do
    it 'no duplica por idempotency_key' do
      op1 = described_class.enqueue(account: account, kind: 'ingest_media', idempotency_key: 'k1', payload: { a: 1 })
      op2 = described_class.enqueue(account: account, kind: 'ingest_media', idempotency_key: 'k1', payload: { a: 2 })
      expect(op1.id).to eq(op2.id)
      expect(described_class.where(account: account, idempotency_key: 'k1').count).to eq(1)
    end
  end

  describe '#schedule_retry! (backoff + agotamiento)' do
    let(:op) { described_class.enqueue(account: account, kind: 'ingest_media', idempotency_key: 'k2') }

    it 'incrementa attempts y agenda el próximo intento' do
      op.schedule_retry!('error temporal')
      expect(op.attempts).to eq(1)
      expect(op.status).to eq('pending')
      expect(op.next_attempt_at).to be_present
      expect(op.last_error).to eq('error temporal')
    end

    it 'pasa a failed al agotar los intentos' do
      described_class::MAX_ATTEMPTS.times { op.schedule_retry!('fallo') }
      expect(op.status).to eq('failed')
      expect(op.next_attempt_at).to be_nil
    end
  end

  describe 'recuperación tras caída del worker (.recover_stale_processing! y .due)' do
    it 'rescata operaciones processing colgadas y deja las recientes' do
      vieja = described_class.create!(account: account, kind: 'ingest_attachment',
                                      idempotency_key: 'stale', status: :processing, payload: {})
      vieja.update_column(:updated_at, (described_class::STALE_PROCESSING_AFTER + 1.minute).ago)
      reciente = described_class.create!(account: account, kind: 'ingest_attachment',
                                         idempotency_key: 'fresh', status: :processing, payload: {})

      # .due incluye la colgada, no la reciente
      expect(described_class.due.pluck(:id)).to include(vieja.id)
      expect(described_class.due.pluck(:id)).not_to include(reciente.id)

      expect(described_class.recover_stale_processing!).to eq(1)
      expect(vieja.reload).to be_pending
      expect(reciente.reload).to be_processing # worker vivo: no se toca
    end
  end

  describe '.due' do
    it 'incluye las pendientes vencidas y excluye las futuras y completadas' do
      vencida = described_class.enqueue(account: account, kind: 'ingest_media', idempotency_key: 'due1')
      vencida.update!(next_attempt_at: 1.minute.ago)
      futura = described_class.enqueue(account: account, kind: 'ingest_media', idempotency_key: 'due2')
      futura.update!(next_attempt_at: 1.hour.from_now)
      completada = described_class.enqueue(account: account, kind: 'ingest_media', idempotency_key: 'due3')
      completada.mark_completed!

      ids = described_class.due.pluck(:id)
      expect(ids).to include(vencida.id)
      expect(ids).not_to include(futura.id, completada.id)
    end
  end
end
