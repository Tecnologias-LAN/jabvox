# == Schema Information
#
# Table name: jabvox_call_logs
#
#  id              :bigint           not null, primary key
#  called_at       :datetime
#  extension       :string           default(""), not null
#  note            :text
#  phone_number    :string           default(""), not null
#  status          :string           default("calling"), not null
#  uniqueid        :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  contact_id      :bigint
#  conversation_id :bigint
#  typification_id :bigint
#  user_id         :bigint           not null
#
# Indexes
#
#  index_jabvox_call_logs_on_account_id       (account_id)
#  index_jabvox_call_logs_on_contact_id       (contact_id)
#  index_jabvox_call_logs_on_conversation_id  (conversation_id)
#  index_jabvox_call_logs_on_typification_id  (typification_id)
#  index_jabvox_call_logs_on_uniqueid         (uniqueid)
#  index_jabvox_call_logs_on_user_id          (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (typification_id => jabvox_typifications.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxCallLog < ApplicationRecord
  self.table_name = 'jabvox_call_logs'

  STATUSES = %w[calling ended typified failed].freeze

  belongs_to :account
  belongs_to :user
  belongs_to :contact, optional: true
  belongs_to :jabvox_lead, optional: true
  belongs_to :conversation, optional: true
  belongs_to :typification, class_name: 'JabvoxTypification', optional: true, foreign_key: :typification_id, inverse_of: :call_logs

  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }
end
