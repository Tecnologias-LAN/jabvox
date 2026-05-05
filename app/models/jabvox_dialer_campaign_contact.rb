# == Schema Information
#
# Table name: jabvox_dialer_campaign_contacts
#
#  id                        :bigint           not null, primary key
#  attempts_jabvox           :integer          default(0), not null
#  last_attempt_at_jabvox    :datetime
#  name_jabvox               :string           default("")
#  phone_jabvox              :string           default(""), not null
#  status_jabvox             :string           default("pending"), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  account_id                :bigint           not null
#  contact_id                :bigint
#  jabvox_dialer_campaign_id :bigint           not null
#
# Indexes
#
#  idx_dialer_contacts_on_campaign_id                      (jabvox_dialer_campaign_id)
#  index_jabvox_dialer_campaign_contacts_on_account_id     (account_id)
#  index_jabvox_dialer_campaign_contacts_on_contact_id     (contact_id)
#  index_jabvox_dialer_campaign_contacts_on_status_jabvox  (status_jabvox)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (jabvox_dialer_campaign_id => jabvox_dialer_campaigns.id)
#
class JabvoxDialerCampaignContact < ApplicationRecord
  self.table_name = 'jabvox_dialer_campaign_contacts'

  STATUSES = %w[pending calling completed failed busy no_answer].freeze

  belongs_to :account
  belongs_to :jabvox_dialer_campaign
  has_many :jabvox_dialer_call_logs,
           inverse_of: :jabvox_dialer_campaign_contact,
           dependent: :destroy

  validates :phone_jabvox, presence: true
  validates :status_jabvox, inclusion: { in: STATUSES }

  scope :pending, -> { where(status_jabvox: 'pending') }
  scope :ordered, -> { order(:created_at) }
end
