# frozen_string_literal: true

# Una fila por LLAMADA individual del Voice Broadcast (cada intento de marcación a un
# destinatario). A diferencia de recipients —que refleja el estado ACTUAL y se
# sobrescribe en cada reintento— aquí queda el histórico completo de cada llamada para
# el reporte: desenlace, AMD, DTMF, duración, grabación y tiempos.
# == Schema Information
#
# Table name: jabvox_voice_broadcast_call_logs
#
#  id                                  :bigint           not null, primary key
#  amd_status_jabvox                   :string
#  answered_at_jabvox                  :datetime
#  attempt_number_jabvox               :integer          default(1), not null
#  dtmf_pressed_jabvox                 :string
#  duration_ms_jabvox                  :integer
#  ended_at_jabvox                     :datetime
#  hangup_cause_jabvox                 :string
#  linkedid_jabvox                     :string
#  name_jabvox                         :string
#  outcome_jabvox                      :string
#  phone_jabvox                        :string           not null
#  played_full_jabvox                  :boolean          default(FALSE), not null
#  recording_file_jabvox               :string
#  ring_ms_jabvox                      :integer
#  started_at_jabvox                   :datetime
#  total_duration_ms_jabvox            :integer
#  uniqueid_jabvox                     :string
#  created_at                          :datetime         not null
#  updated_at                          :datetime         not null
#  account_id                          :bigint           not null
#  contact_id                          :bigint
#  jabvox_voice_broadcast_id           :bigint           not null
#  jabvox_voice_broadcast_recipient_id :bigint           not null
#
# Indexes
#
#  idx_vb_call_logs_account_created  (account_id,created_at)
#  idx_vb_call_logs_broadcast        (jabvox_voice_broadcast_id)
#  idx_vb_call_logs_recipient        (jabvox_voice_broadcast_recipient_id)
#  idx_vb_call_logs_uniqueid         (uniqueid_jabvox)
#
class JabvoxVoiceBroadcastCallLog < ApplicationRecord
  self.table_name = 'jabvox_voice_broadcast_call_logs'

  belongs_to :jabvox_voice_broadcast
  belongs_to :jabvox_voice_broadcast_recipient,
             class_name: 'JabvoxVoiceBroadcastRecipient',
             inverse_of: :call_logs

  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :ordered, -> { order(created_at: :desc) }
end
