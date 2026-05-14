# == Schema Information
#
# Table name: jabvox_dialer_call_logs
#
#  id                                :bigint           not null, primary key
#  agent_id_jabvox                   :bigint
#  duration_jabvox                   :integer          default(0)
#  ended_at_jabvox                   :datetime
#  lead_answered_jabvox              :boolean          default(FALSE), not null
#  notes_jabvox                      :text
#  phone_jabvox                      :string           default(""), not null
#  started_at_jabvox                 :datetime
#  status_jabvox                     :string           default("initiated"), not null
#  created_at                        :datetime         not null
#  updated_at                        :datetime         not null
#  account_id                        :bigint           not null
#  jabvox_dialer_campaign_contact_id :bigint           not null
#  jabvox_dialer_campaign_id         :bigint           not null
#
# Indexes
#
#  idx_dialer_logs_on_campaign_id                      (jabvox_dialer_campaign_id)
#  idx_dialer_logs_on_contact_id                       (jabvox_dialer_campaign_contact_id)
#  index_jabvox_dialer_call_logs_on_account_id         (account_id)
#  index_jabvox_dialer_call_logs_on_started_at_jabvox  (started_at_jabvox)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (jabvox_dialer_campaign_contact_id => jabvox_dialer_campaign_contacts.id)
#  fk_rails_...  (jabvox_dialer_campaign_id => jabvox_dialer_campaigns.id)
#
class JabvoxDialerCallLog < ApplicationRecord
  self.table_name = 'jabvox_dialer_call_logs'

  STATUSES = %w[initiated answered busy no_answer failed].freeze

  belongs_to :account
  belongs_to :jabvox_dialer_campaign
  belongs_to :jabvox_dialer_campaign_contact

  validates :phone_jabvox, presence: true
  validates :status_jabvox, inclusion: { in: STATUSES }

  scope :ordered, -> { order(started_at_jabvox: :desc) }
end
