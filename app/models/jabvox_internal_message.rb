# frozen_string_literal: true

# == Schema Information
#
# Table name: jabvox_internal_messages
#
#  id         :bigint           not null, primary key
#  content    :text             not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  chat_id    :bigint           not null
#  sender_id  :bigint           not null
#
# Indexes
#
#  index_jabvox_internal_messages_on_chat_id    (chat_id)
#  index_jabvox_internal_messages_on_sender_id  (sender_id)
#
# Foreign Keys
#
#  fk_rails_...  (chat_id => jabvox_internal_chats.id)
#  fk_rails_...  (sender_id => users.id)
#
class JabvoxInternalMessage < ApplicationRecord
  belongs_to :chat, class_name: 'JabvoxInternalChat'
  belongs_to :sender, class_name: 'User'

  validates :content, presence: true

  after_create :increment_unread_and_touch_chat

  private

  def increment_unread_and_touch_chat
    chat.members.where.not(user_id: sender_id).update_all('unread_count = unread_count + 1') # rubocop:disable Rails/SkipsModelValidations
    chat.touch # rubocop:disable Rails/SkipsModelValidations
  end
end
