# One row per interval a label was applied to a conversation: applied_at until
# removed_at (NULL = still applied). Lets the WhatsApp report answer "how long did
# this conversation carry label X". Populated from the label_list change on
# Conversation (see Jabvox::ConversationLabelLogging), so it captures changes made
# by agents AND automations. Only counts from deploy onward — no historical
# backfill.
class JabvoxConversationLabelLog < ApplicationRecord
  self.table_name = 'jabvox_conversation_label_logs'

  belongs_to :account
  belongs_to :conversation

  validates :label_jabvox, presence: true
  validates :applied_at_jabvox, presence: true

  scope :open, -> { where(removed_at_jabvox: nil) }
  scope :for_label, ->(label) { where(label_jabvox: label) }

  # Seconds the label was applied; for an open interval, up to `now`.
  def duration_seconds(now = Time.current)
    (removed_at_jabvox || now) - applied_at_jabvox
  end
end
