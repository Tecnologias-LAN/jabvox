# frozen_string_literal: true

# Registro de una llamada del softphone (historial dentro del teléfono): a quién/de quién,
# con qué extensión, dirección, cuándo, cuánto duró y en qué estado terminó.
#
# == Schema
#   account_id, user_id, extension, phone_number, contact_name, direction, status,
#   started_at, answered_at, ended_at, duration_seconds, call_uuid
# == Schema Information
#
# Table name: jabvox_softphone_call_logs
#
#  id               :bigint           not null, primary key
#  answered_at      :datetime
#  call_uuid        :string
#  codec            :string
#  contact_name     :string
#  direction        :integer          default("outbound"), not null
#  duration_seconds :integer          default(0), not null
#  ended_at         :datetime
#  ended_by         :string
#  extension        :string           not null
#  failure_code     :string
#  failure_reason   :string
#  phone_number     :string           not null
#  remote_ip        :string
#  sip_context      :string
#  started_at       :datetime
#  status           :integer          default("ringing"), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  user_id          :bigint           not null
#
# Indexes
#
#  idx_on_account_id_user_id_created_at_b9ba2ecdbd  (account_id,user_id,created_at)
#  index_jabvox_softphone_call_logs_on_account_id   (account_id)
#  index_jabvox_softphone_call_logs_on_call_uuid    (call_uuid)
#  index_jabvox_softphone_call_logs_on_user_id      (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxSoftphoneCallLog < ApplicationRecord
  belongs_to :account
  belongs_to :user
  has_many :jabvox_softphone_call_events, dependent: :destroy

  enum direction: { outbound: 0, inbound: 1 }
  enum status: { ringing: 0, answered: 1, missed: 2, failed: 3, ended: 4 }

  validates :phone_number, presence: true
  validates :extension, presence: true

  scope :recent_first, -> { order(created_at: :desc) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }

  # Cierra la llamada: fija fin, estado y calcula la duración desde answered_at (o started_at).
  def finish!(status: :ended, ended_at: Time.current)
    base = answered_at || started_at
    seconds = base ? [(ended_at - base).round, 0].max : 0
    update!(status: status, ended_at: ended_at, duration_seconds: seconds)
  end
end
