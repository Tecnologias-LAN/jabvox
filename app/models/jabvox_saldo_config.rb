# == Schema Information
#
# Table name: jabvox_saldo_configs
#
#  id                        :bigint           not null, primary key
#  api_key_jabvox            :text
#  api_secret_jabvox         :text
#  balance_updated_at_jabvox :datetime
#  base_url_jabvox           :string           default(""), not null
#  cached_balance_jabvox     :decimal(15, 2)
#  is_active_jabvox          :boolean          default(TRUE), not null
#  name_jabvox               :string           default(""), not null
#  proxy_url_jabvox          :string
#  saldo_username_jabvox     :string           default(""), not null
#  use_proxy_jabvox          :boolean          default(FALSE), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  account_id                :bigint           not null
#
# Indexes
#
#  index_jabvox_saldo_configs_on_account_id  (account_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxSaldoConfig < ApplicationRecord
  self.table_name = 'jabvox_saldo_configs'

  belongs_to :account

  encrypts :api_key_jabvox if Chatwoot.encryption_configured?
  encrypts :api_secret_jabvox if Chatwoot.encryption_configured?

  validates :proxy_url_jabvox, presence: true
  validates :api_key_jabvox, presence: true
  validates :api_secret_jabvox, presence: true

  scope :active, -> { where(is_active_jabvox: true) }
end
