# == Schema Information
#
# Table name: jabvox_sms_messages
#
#  id                     :bigint           not null, primary key
#  error_message          :text
#  message                :text             not null
#  phone                  :string           not null
#  sent_at                :datetime
#  status                 :string           default("pending"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#  contact_id             :bigint
#  external_id            :string
#  jabvox_sms_campaign_id :bigint
#  jabvox_sms_provider_id :bigint
#
# Indexes
#
#  index_jabvox_sms_messages_on_account_id              (account_id)
#  index_jabvox_sms_messages_on_contact_id              (contact_id)
#  index_jabvox_sms_messages_on_jabvox_sms_campaign_id  (jabvox_sms_campaign_id)
#  index_jabvox_sms_messages_on_jabvox_sms_provider_id  (jabvox_sms_provider_id)
#  index_jabvox_sms_messages_on_status                  (status)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (jabvox_sms_campaign_id => jabvox_sms_campaigns.id)
#  fk_rails_...  (jabvox_sms_provider_id => jabvox_sms_providers.id)
#
class JabvoxSmsMessage < ApplicationRecord
  self.table_name = 'jabvox_sms_messages'

  STATUSES = %w[pending sent failed].freeze

  belongs_to :account
  belongs_to :jabvox_sms_campaign, optional: true
  belongs_to :jabvox_sms_provider, optional: true
  belongs_to :contact, optional: true

  validates :phone, presence: true
  validates :message, presence: true
  validates :status, inclusion: { in: STATUSES }
end
