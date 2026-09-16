# A single WhatsApp delivery-status transition for a message, with the real
# timestamp Meta reported. Chatwoot only keeps the latest `messages.status`; this
# log preserves WHEN each transition happened so the WhatsApp agent report can
# measure time-to-delivered and time-to-read. Populated from the status webhook
# (Whatsapp::IncomingMessageBaseService#update_message_with_status).
# == Schema Information
#
# Table name: message_status_events
#
#  id                       :bigint           not null, primary key
#  conversation_origin_type :string
#  error_code               :string
#  error_title              :string
#  occurred_at              :datetime         not null
#  pricing_billable         :boolean
#  pricing_category         :string
#  pricing_model            :string
#  status                   :integer          not null
#  created_at               :datetime         not null
#  account_id               :bigint           not null
#  conversation_id          :bigint
#  inbox_id                 :bigint
#  message_id               :bigint           not null
#  whatsapp_conversation_id :string
#
# Indexes
#
#  idx_message_status_events_account_pricing  (account_id,pricing_category)
#  idx_message_status_events_account_time     (account_id,occurred_at)
#  idx_message_status_events_inbox            (inbox_id)
#  idx_message_status_events_unique           (message_id,status) UNIQUE
#
class MessageStatusEvent < ApplicationRecord
  # Same integer mapping as Message#status so a row's status matches the message.
  enum status: { sent: 0, delivered: 1, read: 2, failed: 3 }

  belongs_to :message
  belongs_to :account

  validates :occurred_at, presence: true
  validates :message_id, uniqueness: { scope: :status }
end
