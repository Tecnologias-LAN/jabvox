# == Schema Information
#
# Table name: jabvox_ai_chat_documents
#
#  id                  :bigint           not null, primary key
#  content_type_jabvox :string(100)
#  is_enabled_jabvox   :boolean          default(TRUE), not null
#  name_jabvox         :string(300)      not null
#  s3_key_jabvox       :string(500)      not null
#  size_jabvox         :bigint           default(0)
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  created_by_id       :bigint
#
# Indexes
#
#  idx_jabvox_ai_chat_docs_key                      (account_id,s3_key_jabvox) UNIQUE
#  index_jabvox_ai_chat_documents_on_account_id     (account_id)
#  index_jabvox_ai_chat_documents_on_created_by_id  (created_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#
class JabvoxAiChatDocument < ApplicationRecord
  include Jabvox::AccountResourceLimit

  belongs_to :account

  # Cuota por cuenta (paquete): docs de IA = AI Chat + Response Bot (suman al mismo tope).
  jabvox_resource_limit :ai_documents,
                        counts_with: %w[JabvoxAiChatDocument JabvoxResponseBotDocument]

  validates :name_jabvox, presence: true, length: { maximum: 300 }
  validates :s3_key_jabvox, presence: true, length: { maximum: 500 }
  validates :s3_key_jabvox, uniqueness: { scope: :account_id }

  scope :enabled, -> { where(is_enabled_jabvox: true) }
  scope :ordered, -> { order(:name_jabvox) }
end
