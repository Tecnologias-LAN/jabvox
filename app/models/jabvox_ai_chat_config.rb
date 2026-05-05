# == Schema Information
#
# Table name: jabvox_ai_chat_configs
#
#  id                        :bigint           not null, primary key
#  bucket_access_key_jabvox  :string(200)
#  bucket_name_jabvox        :string(200)
#  bucket_region_jabvox      :string(50)       default("us-east-1")
#  bucket_secret_key_jabvox  :text
#  bucket_url_jabvox         :string(500)
#  web_search_enabled_jabvox :boolean          default(FALSE), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  account_id                :bigint           not null
#
# Indexes
#
#  index_jabvox_ai_chat_configs_on_account_id  (account_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxAiChatConfig < ApplicationRecord
  belongs_to :account

  validates :bucket_region_jabvox, length: { maximum: 50 }, allow_blank: true
end
