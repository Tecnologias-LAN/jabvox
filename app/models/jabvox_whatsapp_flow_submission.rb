# == Schema Information
#
# Table name: jabvox_whatsapp_flow_submissions
#
#  id                           :bigint           not null, primary key
#  completed_at                 :datetime         not null
#  flow_token                   :string           not null
#  jabvox_whatsapp_flow_version :integer          not null
#  raw_response_json            :jsonb            not null
#  status                       :string           default("completed"), not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  account_id                   :bigint           not null
#  contact_id                   :bigint           not null
#  conversation_id              :bigint
#  jabvox_whatsapp_flow_id      :bigint           not null
#  message_id                   :bigint
#
# Indexes
#
#  idx_jabvox_wa_flow_subs_account_flow                       (account_id,jabvox_whatsapp_flow_id)
#  idx_jabvox_wa_flow_subs_account_flow_token                 (account_id,flow_token) UNIQUE
#  idx_on_jabvox_whatsapp_flow_id_750a893b45                  (jabvox_whatsapp_flow_id)
#  index_jabvox_whatsapp_flow_submissions_on_account_id       (account_id)
#  index_jabvox_whatsapp_flow_submissions_on_contact_id       (contact_id)
#  index_jabvox_whatsapp_flow_submissions_on_conversation_id  (conversation_id)
#  index_jabvox_whatsapp_flow_submissions_on_message_id       (message_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (conversation_id => conversations.id)
#  fk_rails_...  (jabvox_whatsapp_flow_id => jabvox_whatsapp_flows.id)
#  fk_rails_...  (message_id => messages.id)
#
class JabvoxWhatsappFlowSubmission < ApplicationRecord
  self.table_name = 'jabvox_whatsapp_flow_submissions'

  belongs_to :account
  belongs_to :jabvox_whatsapp_flow
  belongs_to :contact
  belongs_to :conversation, optional: true
  belongs_to :message, optional: true
  has_many :answers, class_name: 'JabvoxWhatsappFlowAnswer', dependent: :destroy,
                      foreign_key: :jabvox_whatsapp_flow_submission_id, inverse_of: :submission

  # Meta only ever delivers completed Flow responses (no partial-submission webhook exists
  # today) — the column stays free text rather than an enum so a future partial/abandoned
  # state can be added without a migration, per the architecture doc's "extensible" intent.
  validates :flow_token, presence: true
  validates :jabvox_whatsapp_flow_version, presence: true
  validates :completed_at, presence: true

  scope :by_flow, ->(flow_id) { where(jabvox_whatsapp_flow_id: flow_id) if flow_id.present? }
  scope :recent_first, -> { order(completed_at: :desc) }
end
