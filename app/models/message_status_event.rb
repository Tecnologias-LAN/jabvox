# A single WhatsApp delivery-status transition for a message, with the real
# timestamp Meta reported. Chatwoot only keeps the latest `messages.status`; this
# log preserves WHEN each transition happened so the WhatsApp agent report can
# measure time-to-delivered and time-to-read. Populated from the status webhook
# (Whatsapp::IncomingMessageBaseService#update_message_with_status).
class MessageStatusEvent < ApplicationRecord
  # Same integer mapping as Message#status so a row's status matches the message.
  enum status: { sent: 0, delivered: 1, read: 2, failed: 3 }

  belongs_to :message
  belongs_to :account

  validates :occurred_at, presence: true
  validates :message_id, uniqueness: { scope: :status }
end
