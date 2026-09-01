# One row per interval a label was applied to a conversation: applied_at until
# removed_at (NULL = still applied). Lets the WhatsApp report answer "how long did
# this conversation carry label X". Populated from the label_list change on
# Conversation (see Jabvox::ConversationLabelLogging), so it captures changes made
# by agents AND automations. Only counts from deploy onward — no historical
# backfill.
# == Schema Information
#
# Table name: jabvox_conversation_label_logs
#
#  id                :bigint           not null, primary key
#  applied_at_jabvox :datetime         not null
#  label_jabvox      :string           not null
#  removed_at_jabvox :datetime
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :integer          not null
#  conversation_id   :integer          not null
#
# Indexes
#
#  idx_conv_label_logs_account_applied_keyset  (account_id,applied_at_jabvox DESC,id DESC)
#  idx_conv_label_logs_account_label           (account_id,label_jabvox)
#  idx_conv_label_logs_account_removed_keyset  (account_id,removed_at_jabvox DESC,id DESC)
#  idx_conv_label_logs_conversation            (conversation_id)
#  idx_conv_label_logs_open_unique             (conversation_id,label_jabvox) UNIQUE WHERE (removed_at_jabvox IS NULL)
#
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
