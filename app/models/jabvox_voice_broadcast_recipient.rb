# frozen_string_literal: true

# Un destinatario del voice broadcast: su teléfono, el estado de marcación y el
# desenlace final (contestó humano/máquina, escuchó el audio completo, DTMF, etc.).
# == Schema Information
#
# Table name: jabvox_voice_broadcast_recipients
#
#  id                        :bigint           not null, primary key
#  amd_status_jabvox         :string
#  answered_at_jabvox        :datetime
#  attempts_jabvox           :integer          default(0), not null
#  dtmf_pressed_jabvox       :string
#  duration_ms_jabvox        :integer
#  last_attempt_at_jabvox    :datetime
#  linkedid_jabvox           :string
#  name_jabvox               :string
#  outcome_jabvox            :string
#  phone_jabvox              :string           not null
#  played_full_jabvox        :boolean          default(FALSE), not null
#  recording_file_jabvox     :string
#  ring_ms_jabvox            :integer
#  status_jabvox             :string           default("pending"), not null
#  uniqueid_jabvox           :string
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  account_id                :bigint           not null
#  contact_id                :bigint
#  jabvox_voice_broadcast_id :bigint           not null
#
# Indexes
#
#  idx_vbr_account           (account_id)
#  idx_vbr_account_uniqueid  (account_id,uniqueid_jabvox) WHERE (uniqueid_jabvox IS NOT NULL)
#  idx_vbr_broadcast         (jabvox_voice_broadcast_id)
#  idx_vbr_broadcast_status  (jabvox_voice_broadcast_id,status_jabvox)
#  idx_vbr_unique_phone      (jabvox_voice_broadcast_id,phone_jabvox) UNIQUE
#
class JabvoxVoiceBroadcastRecipient < ApplicationRecord
  self.table_name = 'jabvox_voice_broadcast_recipients'

  # Estado de MARCACIÓN (control de flujo del motor).
  STATUSES = %w[pending calling done failed].freeze
  # Desenlace FINAL de la llamada (para el reporte).
  OUTCOMES = %w[
    answered_human answered_machine no_answer busy congestion failed
    played_complete hung_up_early opted_out
  ].freeze
  AMD_STATUSES = %w[HUMAN MACHINE NOTSURE].freeze
  # Outcomes que ameritan reintento (los demás son terminales).
  RETRYABLE_OUTCOMES = %w[no_answer busy congestion].freeze

  belongs_to :jabvox_voice_broadcast
  belongs_to :account
  # Histórico de cada llamada individual (una fila por intento; recipients solo guarda
  # el estado actual). Ver JabvoxVoiceBroadcastCallLog.
  has_many :call_logs, class_name: 'JabvoxVoiceBroadcastCallLog',
                       inverse_of: :jabvox_voice_broadcast_recipient, dependent: :destroy

  validates :phone_jabvox, presence: true
  validates :status_jabvox, inclusion: { in: STATUSES }
  validates :outcome_jabvox, inclusion: { in: OUTCOMES }, allow_nil: true

  scope :for_broadcast, ->(id) { where(jabvox_voice_broadcast_id: id) }
  scope :pending, -> { where(status_jabvox: 'pending') }
  scope :calling, -> { where(status_jabvox: 'calling') }

  # ¿Se puede reintentar este destinatario dado el desenlace ACTUAL del evento?
  # Recibe el outcome explícito (no lee outcome_jabvox, que puede aún no estar
  # persistido cuando el event handler decide el estado).
  # Semántica de max_retries (nº de reintentos ADEMÁS del primer intento):
  #   0 = SIN reintentos → 1 sola llamada (valor por defecto, el más seguro).
  #   n = hasta n reintentos → n+1 llamadas totales.
  # NUNCA es ilimitado: se aplica un TOPE DURO absoluto (MAX_RETRIES_HARD_CAP) por si
  # se colara un valor mayor por cualquier vía, para no marcar infinitamente.
  def retryable?(max_retries, outcome = outcome_jabvox)
    return false unless RETRYABLE_OUTCOMES.include?(outcome)

    # Tope efectivo: nunca por encima del cap duro, nunca negativo (ilimitado).
    m = max_retries.to_i.clamp(0, JabvoxVoiceBroadcast::MAX_RETRIES_HARD_CAP)
    # attempts ya incluye el intento en curso (se incrementó al reservar). Con m=0,
    # tras el 1er intento attempts=1 > 0 → no reintenta (1 sola llamada).
    attempts_jabvox.to_i <= m
  end
end
