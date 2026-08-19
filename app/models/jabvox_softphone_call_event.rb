# frozen_string_literal: true

# Un evento dentro de una llamada del softphone (traza para diagnóstico): registro,
# invite, contestada, DTMF, hold, transferencia, colgado o error. Permite reconstruir qué
# pasó en cada llamada desde el panel.
#
# == Schema
#   account_id, jabvox_softphone_call_log_id, event_type, detail, occurred_at
# == Schema Information
#
# Table name: jabvox_softphone_call_events
#
#  id                           :bigint           not null, primary key
#  detail                       :string
#  event_type                   :string           not null
#  occurred_at                  :datetime         not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  account_id                   :bigint           not null
#  jabvox_softphone_call_log_id :bigint           not null
#
# Indexes
#
#  idx_on_account_id_occurred_at_0799b713a5          (account_id,occurred_at)
#  idx_sp_events_on_call_log                         (jabvox_softphone_call_log_id)
#  index_jabvox_softphone_call_events_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (jabvox_softphone_call_log_id => jabvox_softphone_call_logs.id)
#
class JabvoxSoftphoneCallEvent < ApplicationRecord
  belongs_to :account
  belongs_to :jabvox_softphone_call_log

  TYPES = %w[registered invite answer dtmf hold transfer hangup error].freeze

  validates :event_type, presence: true
  validates :occurred_at, presence: true

  scope :chronological, -> { order(:occurred_at) }
end
