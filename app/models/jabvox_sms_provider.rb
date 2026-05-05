# == Schema Information
#
# Table name: jabvox_sms_providers
#
#  id           :bigint           not null, primary key
#  active       :boolean          default(TRUE), not null
#  api_password :text
#  api_user     :string           not null
#  base_url     :string           not null
#  name         :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#
# Indexes
#
#  index_jabvox_sms_providers_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxSmsProvider < ApplicationRecord
  self.table_name = 'jabvox_sms_providers'

  belongs_to :account
  has_many :jabvox_sms_campaigns, foreign_key: :jabvox_sms_provider_id, dependent: :nullify
  has_many :jabvox_sms_messages, foreign_key: :jabvox_sms_provider_id, dependent: :nullify

  validates :name, presence: true
  validates :base_url, presence: true
  validates :api_user, presence: true
  validates :api_password, presence: true, on: :create
end
