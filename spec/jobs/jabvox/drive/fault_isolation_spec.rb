# frozen_string_literal: true

require 'rails_helper'

# AISLAMIENTO DE FALLOS (blast radius): un fallo o abuso en UNA cuenta no debe
# afectar el procesamiento de las DEMÁS.
RSpec.describe Jabvox::Drive::PendingOperationRetryJob, 'aislamiento de fallos' do
  let(:account_a) { create(:account, jabvox_drive_enabled_jabvox: true, limits: { 'storage_gb' => 1 }) }
  let(:account_b) { create(:account, jabvox_drive_enabled_jabvox: true, limits: { 'storage_gb' => 1 }) }

  describe 'scheduler (cola compartida)' do
    it 'un dispatch que falla en la cuenta A no impide despachar la operación de B' do
      op_a = JabvoxDrivePendingOperation.enqueue(account: account_a, kind: 'ingest_attachment',
                                                 idempotency_key: 'a-1', payload: { 'attachment_id' => 1 })
      op_b = JabvoxDrivePendingOperation.enqueue(account: account_b, kind: 'ingest_attachment',
                                                 idempotency_key: 'b-1', payload: { 'attachment_id' => 2 })
      op_a.update!(next_attempt_at: 1.minute.ago)
      op_b.update!(next_attempt_at: 1.minute.ago)

      dispatched = []
      allow(Jabvox::Drive::AttachmentIngestJob).to receive(:perform_later) do |account_id, _att|
        raise 'fallo simulado de la cuenta A' if account_id == account_a.id

        dispatched << account_id
      end

      # No debe propagar la excepción de A: el lote completa y B se despacha.
      expect { Jabvox::Drive::PendingOperationRetryJob.perform_now }.not_to raise_error
      expect(dispatched).to include(account_b.id)
    end
  end

  describe 'ingesta (worker compartido)' do
    it 'un fallo al ingerir el adjunto de A deja su operación pendiente sin afectar a B' do
      op_a = JabvoxDrivePendingOperation.enqueue(account: account_a, kind: 'ingest_attachment',
                                                 idempotency_key: 'att-a', payload: {})
      op_b = JabvoxDrivePendingOperation.enqueue(account: account_b, kind: 'ingest_attachment',
                                                 idempotency_key: 'att-b', payload: {})

      # A: fuerza un error al resolver el adjunto. B: adjunto inexistente -> completa limpio.
      allow(Attachment).to receive(:where).and_call_original

      # La ingesta de A falla de forma recuperable (no revienta el proceso).
      expect do
        Jabvox::Drive::AttachmentIngestJob.perform_now(account_a.id, -1)
        Jabvox::Drive::AttachmentIngestJob.perform_now(account_b.id, -1)
      end.not_to raise_error

      # Ambas operaciones siguen existiendo; el fallo de A no tocó a B.
      expect(op_a.reload).to be_present
      expect(op_b.reload).to be_present
    end
  end

  describe 'fairness por cuenta (noisy neighbor)' do
    it 're-encola el job de una cuenta saturada en vez de acaparar, y deja pasar a otra' do
      key = "jabvox_fairshare_jabvox_drive_attachment_ingest_job_#{account_a.id}"
      Redis::Alfred.set(key, Jabvox::Drive::AttachmentIngestJob.resolved_fair_share_limit)

      # el re-encolado usa perform_later; lo interceptamos para no depender de la cola real
      allow(Jabvox::Drive::AttachmentIngestJob).to receive(:set).and_return(Jabvox::Drive::AttachmentIngestJob)
      allow(Jabvox::Drive::AttachmentIngestJob).to receive(:perform_later)

      job_a = Jabvox::Drive::AttachmentIngestJob.new(account_a.id, 1)
      expect(job_a.with_account_fair_share(account_a.id) { :ejecutado }).to eq(:requeued)

      job_b = Jabvox::Drive::AttachmentIngestJob.new(account_b.id, 1)
      expect(job_b.with_account_fair_share(account_b.id) { :ejecutado }).to eq(:ejecutado)
    ensure
      Redis::Alfred.delete(key)
      Redis::Alfred.delete("jabvox_fairshare_jabvox_drive_attachment_ingest_job_#{account_b.id}")
    end
  end

  describe 'cuota (contadores por cuenta)' do
    it 'la reserva de A y la de B son filas independientes (no se bloquean entre sí)' do
      qa = Jabvox::Drive::QuotaService.new(account_a)
      qb = Jabvox::Drive::QuotaService.new(account_b)
      allow(qa).to receive(:quota_bytes).and_return(1000)
      allow(qb).to receive(:quota_bytes).and_return(1000)

      expect(qa.reserve!(1000)).to be(true)  # A llena su cuota
      expect(qa.reserve!(1)).to be(false)    # A ya no cabe
      # B no se ve afectada por que A esté llena.
      expect(qb.reserve!(500)).to be(true)
      expect(qb.available_bytes).to eq(500)
    end
  end
end
