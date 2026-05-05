# == Schema Information
#
# Table name: jabvox_affiliate_ip_whitelists
#
#  id                  :bigint           not null, primary key
#  comment             :text
#  ip                  :string(45)       not null
#  is_active           :boolean          default(TRUE), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  jabvox_affiliate_id :bigint           not null
#
# Indexes
#
#  idx_affiliate_ip_whitelists_on_affiliate_and_ip              (jabvox_affiliate_id,ip) UNIQUE
#  index_jabvox_affiliate_ip_whitelists_on_jabvox_affiliate_id  (jabvox_affiliate_id)
#
# Foreign Keys
#
#  fk_rails_...  (jabvox_affiliate_id => jabvox_affiliates.id)
#
class JabvoxAffiliateIpWhitelist < ApplicationRecord
  self.table_name = 'jabvox_affiliate_ip_whitelists'

  belongs_to :jabvox_affiliate

  validates :ip, presence: true, length: { maximum: 45 }
  validates :ip, uniqueness: { scope: :jabvox_affiliate_id }
  validates :ip, format: {
    with: /\A(\d{1,3}\.){3}\d{1,3}\z/,
    message: 'must be a valid IPv4 address'
  }

  scope :active, -> { where(is_active: true) }
  scope :ordered, -> { order(:created_at) }
end
