# frozen_string_literal: true

# == Schema Information
#
# Table name: jabvox_internal_chats
#
#  id            :bigint           not null, primary key
#  chat_type     :integer          default("direct"), not null
#  name          :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  created_by_id :bigint           not null
#
# Indexes
#
#  index_jabvox_internal_chats_on_account_id     (account_id)
#  index_jabvox_internal_chats_on_created_by_id  (created_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#
class JabvoxInternalChat < ApplicationRecord
  belongs_to :account
  belongs_to :created_by, class_name: 'User'
  has_many :members, class_name: 'JabvoxInternalChatMember', foreign_key: :chat_id, inverse_of: :chat, dependent: :destroy
  has_many :users, through: :members
  has_many :messages, class_name: 'JabvoxInternalMessage', foreign_key: :chat_id, inverse_of: :chat, dependent: :destroy

  enum chat_type: { direct: 0, group_chat: 1 }

  validates :name, presence: true, if: :group_chat?

  scope :for_user, ->(user_id) { joins(:members).where(jabvox_internal_chat_members: { user_id: user_id }) }
  scope :ordered, -> { order(updated_at: :desc) }
end
