# == Schema Information
#
# Table name: jabvox_ip_whitelists
#
#  id         :bigint           not null, primary key
#  comment    :text
#  ip         :string(45)       not null
#  is_active  :boolean          default(TRUE), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  index_jabvox_ip_whitelists_on_account_id         (account_id)
#  index_jabvox_ip_whitelists_on_account_id_and_ip  (account_id,ip) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxIpWhitelist < ApplicationRecord
  self.table_name = 'jabvox_ip_whitelists'

  belongs_to :account

  validates :ip, presence: true, length: { maximum: 45 }
  validates :ip, uniqueness: { scope: :account_id }
  validates :ip, format: {
    with: /\A(\d{1,3}\.){3}\d{1,3}\z/,
    message: 'must be a valid IPv4 address'
  }

  scope :active, -> { where(is_active: true) }
  scope :ordered, -> { order(:created_at) }
end
