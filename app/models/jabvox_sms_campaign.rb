# == Schema Information
#
# Table name: jabvox_sms_campaigns
#
#  id                     :bigint           not null, primary key
#  affiliate_ids_sms      :jsonb
#  contact_ids            :jsonb
#  description            :text
#  failed_count           :integer          default(0), not null
#  inbox_ids_sms          :jsonb
#  message                :text             not null
#  name                   :string           not null
#  sent_count             :integer          default(0), not null
#  status                 :string           default("draft"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#  jabvox_campaign_id     :bigint
#  jabvox_sms_provider_id :bigint
#
# Indexes
#
#  index_jabvox_sms_campaigns_on_account_id              (account_id)
#  index_jabvox_sms_campaigns_on_jabvox_sms_provider_id  (jabvox_sms_provider_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (jabvox_campaign_id => jabvox_campaigns.id) ON DELETE => nullify
#  fk_rails_...  (jabvox_sms_provider_id => jabvox_sms_providers.id)
#
class JabvoxSmsCampaign < ApplicationRecord
  self.table_name = 'jabvox_sms_campaigns'

  STATUSES = %w[draft active paused completed].freeze

  belongs_to :account
  belongs_to :jabvox_sms_provider, optional: true
  has_many :jabvox_sms_messages, foreign_key: :jabvox_sms_campaign_id, dependent: :destroy

  validates :name, presence: true
  validates :message, presence: true
  validates :status, inclusion: { in: STATUSES }
end
