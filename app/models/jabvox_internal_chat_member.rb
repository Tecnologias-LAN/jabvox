# frozen_string_literal: true

# == Schema Information
#
# Table name: jabvox_internal_chat_members
#
#  id           :bigint           not null, primary key
#  last_read_at :datetime
#  unread_count :integer          default(0), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  chat_id      :bigint           not null
#  user_id      :bigint           not null
#
# Indexes
#
#  index_jabvox_internal_chat_members_on_chat_id              (chat_id)
#  index_jabvox_internal_chat_members_on_chat_id_and_user_id  (chat_id,user_id) UNIQUE
#  index_jabvox_internal_chat_members_on_user_id              (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (chat_id => jabvox_internal_chats.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxInternalChatMember < ApplicationRecord
  belongs_to :chat, class_name: 'JabvoxInternalChat'
  belongs_to :user

  validates :user_id, uniqueness: { scope: :chat_id }
end
