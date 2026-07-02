# == Schema Information
#
# Table name: jabvox_ai_chat_configs
#
#  id                          :bigint           not null, primary key
#  bucket_access_key_jabvox    :string(200)
#  bucket_name_jabvox          :string(200)
#  bucket_region_jabvox        :string(50)       default("us-east-1")
#  bucket_secret_key_jabvox    :text
#  bucket_url_jabvox           :string(500)
#  web_search_enabled_jabvox   :boolean          default(FALSE), not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  account_id                  :bigint           not null
#  documents_storage_jabvox_id :bigint
#
# Indexes
#
#  index_jabvox_ai_chat_configs_on_account_id                   (account_id) UNIQUE
#  index_jabvox_ai_chat_configs_on_documents_storage_jabvox_id  (documents_storage_jabvox_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (documents_storage_jabvox_id => jabvox_ai_chat_storages.id) ON DELETE => nullify
#
class JabvoxAiChatConfig < ApplicationRecord
  belongs_to :account
  # Optional storage bucket for documents. When set, AI Chat lists/reads documents
  # from this storage instead of its own inline bucket_*_jabvox columns.
  belongs_to :documents_storage_jabvox, class_name: 'JabvoxAiChatStorage', optional: true

  encrypts :bucket_access_key_jabvox if Jabvox.encryption_configured?
  encrypts :bucket_secret_key_jabvox if Jabvox.encryption_configured?

  validates :bucket_region_jabvox, length: { maximum: 50 }, allow_blank: true
  # The chosen shared storage must belong to the same account (prevents pointing
  # documents at another tenant's bucket via a forged id).
  validate :documents_storage_belongs_to_account

  # The credentials source AI Chat should use for documents: the chosen shared
  # storage if one is set, otherwise this config's own inline bucket fields.
  def documents_bucket_source
    documents_storage_jabvox || self
  end

  private

  def documents_storage_belongs_to_account
    return if documents_storage_jabvox_id.blank?
    return if documents_storage_jabvox&.account_id == account_id

    errors.add(:documents_storage_jabvox_id, 'is not a valid storage for this account')
  end
end
