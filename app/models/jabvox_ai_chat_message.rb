# == Schema Information
#
# Table name: jabvox_ai_chat_messages
#
#  id                :bigint           not null, primary key
#  content_jabvox    :text             not null
#  metadata_jabvox   :jsonb
#  role_jabvox       :string(20)       not null
#  session_id_jabvox :string(100)      not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  user_id           :bigint           not null
#
# Indexes
#
#  idx_jabvox_ai_chat_messages_session          (account_id,user_id,session_id_jabvox)
#  idx_jabvox_ai_chat_messages_user             (account_id,user_id)
#  index_jabvox_ai_chat_messages_on_account_id  (account_id)
#  index_jabvox_ai_chat_messages_on_user_id     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxAiChatMessage < ApplicationRecord
  ROLES = %w[user assistant].freeze

  belongs_to :account
  belongs_to :user

  validates :session_id_jabvox, presence: true, length: { maximum: 100 }
  validates :role_jabvox, presence: true, inclusion: { in: ROLES }
  validates :content_jabvox, presence: true

  scope :for_session, ->(session_id) { where(session_id_jabvox: session_id).order(:created_at) }
  scope :recent_for_session, ->(session_id) { for_session(session_id).last(20) }
end
