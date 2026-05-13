# == Schema Information
#
# Table name: jabvox_voip_configs
#
#  id               :bigint           not null, primary key
#  context          :string           default("clicktocall"), not null
#  dialer_context   :string           default("")
#  dialer_trunk     :string           default(""), not null
#  host             :string           default(""), not null
#  password         :text
#  port             :integer          default(5038), not null
#  username         :string           default(""), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  dialer_caller_id :string           default(""), not null
#
# Indexes
#
#  index_jabvox_voip_configs_on_account_id  (account_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxVoipConfig < ApplicationRecord
  self.table_name = 'jabvox_voip_configs'

  belongs_to :account

  encrypts :password if Chatwoot.encryption_configured?

  validates :host, presence: true
  validates :username, presence: true
  validates :context, presence: true
  validates :port, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 65_535 }
end
