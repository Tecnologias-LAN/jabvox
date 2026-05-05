# == Schema Information
#
# Table name: jabvox_ai_chat_models
#
#  id                :bigint           not null, primary key
#  api_key_jabvox    :text
#  base_url_jabvox   :string(500)
#  is_default_jabvox :boolean          default(FALSE), not null
#  model_jabvox      :string(200)      not null
#  name_jabvox       :string(150)      not null
#  provider_jabvox   :string(50)       not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#
# Indexes
#
#  index_jabvox_ai_chat_models_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxAiChatModel < ApplicationRecord
  PROVIDERS = %w[openai groq anthropic ollama lmstudio custom].freeze

  belongs_to :account

  validates :name_jabvox, presence: true, length: { maximum: 150 }
  validates :provider_jabvox, length: { maximum: 50 }, allow_blank: true
  validates :model_jabvox, presence: true, length: { maximum: 200 }
  validates :base_url_jabvox, length: { maximum: 500 }, allow_blank: true
  validate :only_one_default_per_account

  before_validation :set_default_provider

  scope :ordered, -> { order(:name_jabvox) }
  scope :defaults, -> { where(is_default_jabvox: true) }

  def self.default_for(account_id)
    where(account_id: account_id, is_default_jabvox: true).first
  end

  private

  def only_one_default_per_account
    return unless is_default_jabvox?
    return if account.jabvox_ai_chat_models.where(is_default_jabvox: true).where.not(id: id).none?

    errors.add(:is_default_jabvox, 'only one model can be the default')
  end

  def set_default_provider
    self.provider_jabvox = 'custom' if provider_jabvox.blank?
  end
end
