# == Schema Information
#
# Table name: jabvox_dialer_campaigns
#
#  id                          :bigint           not null, primary key
#  affiliate_ids_jabvox        :jsonb
#  agent_ids_jabvox            :jsonb
#  answered_count_jabvox       :integer          default(0), not null
#  caller_id_jabvox            :string           default("")
#  calling_hours_end_jabvox    :string           default("18:00")
#  calling_hours_start_jabvox  :string           default("08:00")
#  countries_jabvox            :jsonb
#  description_jabvox          :text
#  dialed_count_jabvox         :integer          default(0), not null
#  failed_count_jabvox         :integer          default(0), not null
#  inbox_ids_jabvox            :jsonb
#  leads_count_jabvox          :integer          default(0), not null
#  lines_per_agent_jabvox      :integer          default(1)
#  management_state_ids_jabvox :jsonb
#  max_concurrent_jabvox       :integer          default(1), not null
#  name_jabvox                 :string           default(""), not null
#  retry_count_jabvox          :integer          default(0), not null
#  retry_interval_jabvox       :integer          default(60), not null
#  status_jabvox               :string           default("draft"), not null
#  total_contacts_jabvox       :integer          default(0), not null
#  wrapup_time_jabvox          :integer          default(30)
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  account_id                  :bigint           not null
#  jabvox_campaign_id          :bigint
#
# Indexes
#
#  index_jabvox_dialer_campaigns_on_account_id          (account_id)
#  index_jabvox_dialer_campaigns_on_jabvox_campaign_id  (jabvox_campaign_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (jabvox_campaign_id => jabvox_campaigns.id) ON DELETE => nullify
#
class JabvoxDialerCampaign < ApplicationRecord
  self.table_name = 'jabvox_dialer_campaigns'

  STATUSES = %w[draft active paused completed].freeze
  CALL_STATUSES = %w[initiated answered busy no_answer failed].freeze

  belongs_to :account
  belongs_to :jabvox_campaign, optional: true
  has_many :jabvox_dialer_campaign_contacts,
           inverse_of: :jabvox_dialer_campaign,
           dependent: :destroy
  has_many :jabvox_dialer_call_logs,
           inverse_of: :jabvox_dialer_campaign,
           dependent: :destroy

  validates :name_jabvox, presence: true
  validates :status_jabvox, inclusion: { in: STATUSES }
  validates :max_concurrent_jabvox, numericality: { only_integer: true, greater_than: 0 }
  validates :retry_count_jabvox, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :retry_interval_jabvox, numericality: { only_integer: true, greater_than: 0 }

  scope :ordered, -> { order(created_at: :desc) }
  scope :active, -> { where(status_jabvox: 'active') }
end
