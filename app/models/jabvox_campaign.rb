# == Schema Information
#
# Table name: jabvox_campaigns
#
#  id          :bigint           not null, primary key
#  name_jabvox :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
# Indexes
#
#  index_jabvox_campaigns_on_account_id                  (account_id)
#  index_jabvox_campaigns_on_account_id_and_name_jabvox  (account_id,name_jabvox) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxCampaign < ApplicationRecord
  belongs_to :account
  has_many :jabvox_leads, dependent: :nullify

  validates :name_jabvox, presence: true, uniqueness: { scope: :account_id }
  validates :account_id, presence: true

  scope :ordered, -> { order(name_jabvox: :asc) }
end
