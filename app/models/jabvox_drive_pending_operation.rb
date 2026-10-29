# frozen_string_literal: true

# Operación pendiente del Drive. Cola DURABLE (en PostgreSQL) que sobrevive a
# caídas de MinIO y reinicios de la app/workers. La ingesta de medios de WhatsApp
# y las copias overflow->principal se registran aquí ANTES de tocar MinIO, para
# que ningún adjunto se pierda y los reintentos sean seguros e idempotentes.
#
# kind: ingest_attachment (camino principal, cualquier bandeja) | ingest_media
#       (WhatsApp vía media_id, opcional) | move_to_primary | reconcile | delete_object
# status: pending | processing | completed | failed
#
# == Schema Information
#
# Table name: jabvox_drive_pending_operations
#
#  id              :bigint           not null, primary key
#  attempts        :integer          default(0), not null
#  idempotency_key :string           not null
#  kind            :string           not null
#  last_error      :text
#  next_attempt_at :datetime
#  payload         :jsonb            not null
#  status          :integer          default("pending"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#
# Indexes
#
#  idx_drive_pending_unique_key                         (account_id,idempotency_key) UNIQUE
#  idx_on_status_next_attempt_at_53f7587c2e             (status,next_attempt_at)
#  index_jabvox_drive_pending_operations_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxDrivePendingOperation < ApplicationRecord
  belongs_to :account

  enum status: { pending: 0, processing: 1, completed: 2, failed: 3 }

  validates :kind, :idempotency_key, presence: true
  validates :idempotency_key, uniqueness: { scope: :account_id }

  MAX_ATTEMPTS = 8
  # Si una operación lleva más de esto en `processing`, asumimos que el worker murió
  # a mitad (reinicio/OOM/crash) y la rescatamos. El procesamiento es idempotente, así
  # que reintentarla es seguro aunque el proceso anterior hubiera avanzado algo.
  STALE_PROCESSING_AFTER = 15.minutes

  # Operaciones listas para (re)procesar: las pendientes vencidas Y las que quedaron
  # colgadas en `processing` (worker caído). Esto garantiza que, tras un reinicio del
  # server o una caída del worker, NADA se queda atascado: el cron las recupera.
  scope :due, lambda {
    where(status: :pending)
      .where('next_attempt_at IS NULL OR next_attempt_at <= ?', Time.current)
      .or(where(status: :processing).where(updated_at: ..STALE_PROCESSING_AFTER.ago))
  }

  # Recupera operaciones `processing` colgadas devolviéndolas a `pending` para que el
  # scheduler las vuelva a despachar. Idempotente.
  def self.recover_stale_processing!
    # update_all deliberado: rescate en bloque, sin callbacks, idempotente.
    where(status: :processing).where(updated_at: ..STALE_PROCESSING_AFTER.ago)
                              .update_all(status: statuses[:pending], next_attempt_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  # Registra una operación de forma idempotente: si ya existe la clave, la
  # devuelve sin duplicar (reintentos seguros).
  def self.enqueue(account:, kind:, idempotency_key:, payload: {})
    find_or_create_by!(account: account, idempotency_key: idempotency_key) do |op|
      op.kind = kind
      op.payload = payload
      op.status = :pending
      op.next_attempt_at = Time.current
    end
  end

  # Backoff exponencial con jitter para el siguiente intento.
  def schedule_retry!(error_message)
    self.attempts += 1
    self.last_error = error_message.to_s.first(2000)
    if attempts >= MAX_ATTEMPTS
      self.status = :failed
      self.next_attempt_at = nil
    else
      base = (2**attempts)
      jitter = rand(0..(base / 2.0))
      self.status = :pending
      self.next_attempt_at = Time.current + (base + jitter).seconds
    end
    save!
  end

  def mark_completed!
    update!(status: :completed, last_error: nil, next_attempt_at: nil)
  end
end
