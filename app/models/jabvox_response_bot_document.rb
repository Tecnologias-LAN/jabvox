# == Schema Information
#
# Table name: jabvox_response_bot_documents
#
#  id                    :bigint           not null, primary key
#  content_type_jabvox   :string
#  enabled_jabvox        :boolean          default(TRUE), not null
#  label_category_jabvox :string
#  name_jabvox           :string           not null
#  s3_key_jabvox         :string           not null
#  size_jabvox           :bigint
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#
# Indexes
#
#  idx_on_account_id_label_category_jabvox_d9404a8152  (account_id,label_category_jabvox)
#  idx_on_account_id_s3_key_jabvox_1dc58f075a          (account_id,s3_key_jabvox) UNIQUE
#  index_jabvox_response_bot_documents_on_account_id   (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxResponseBotDocument < ApplicationRecord
  CATEGORIES = JabvoxResponseBotConfig::LABEL_CATEGORIES

  belongs_to :account

  validates :name_jabvox, presence: true
  validates :s3_key_jabvox, presence: true, uniqueness: { scope: :account_id }
  validates :label_category_jabvox, inclusion: { in: CATEGORIES }, allow_nil: true

  scope :enabled, -> { where(enabled_jabvox: true) }
  scope :ordered, -> { order(:name_jabvox) }
  scope :for_category, ->(cat) { where(label_category_jabvox: cat) }
end
