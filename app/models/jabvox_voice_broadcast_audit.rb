# frozen_string_literal: true

# Traza de auditoría de acciones sensibles del voice broadcast (marcación automática):
# quién subió el audio, lanzó, pausó, reanudó o detuvo qué broadcast y cuándo.
# == Schema Information
#
# Table name: jabvox_voice_broadcast_audits
#
#  id                        :bigint           not null, primary key
#  action_jabvox             :string           not null
#  metadata_jabvox           :jsonb            not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  account_id                :bigint           not null
#  jabvox_voice_broadcast_id :bigint           not null
#  user_id                   :bigint
#
# Indexes
#
#  idx_vba_account_time  (account_id,created_at)
#  idx_vba_broadcast     (jabvox_voice_broadcast_id)
#
class JabvoxVoiceBroadcastAudit < ApplicationRecord
  self.table_name = 'jabvox_voice_broadcast_audits'

  ACTIONS = %w[created audio_uploaded started paused resumed stopped].freeze

  belongs_to :jabvox_voice_broadcast
  belongs_to :account
  belongs_to :user, optional: true

  validates :action_jabvox, inclusion: { in: ACTIONS }

  scope :recent_first, -> { order(created_at: :desc) }

  # Registra una acción de auditoría. No debe tumbar la operación si falla.
  def self.record(broadcast, user_id, action, metadata = {})
    create!(jabvox_voice_broadcast_id: broadcast.id, account_id: broadcast.account_id,
            user_id: user_id, action_jabvox: action, metadata_jabvox: metadata)
  rescue StandardError => e
    Rails.logger.warn "[VoiceBroadcast] audit failed | #{e.message}"
    nil
  end
end
