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
#  uniqueid_jabvox                   :string
#  created_at                        :datetime         not null
#  updated_at                        :datetime         not null
#  account_id                        :bigint           not null
#  jabvox_dialer_campaign_contact_id :bigint           not null
#  jabvox_dialer_campaign_id         :bigint           not null
#  typification_id                   :bigint
#
# Indexes
#
#  idx_dialer_logs_agent_open                          (agent_id_jabvox,ended_at_jabvox)
#  idx_dialer_logs_on_agent_id                         (agent_id_jabvox)
#  idx_dialer_logs_on_campaign_id                      (jabvox_dialer_campaign_id)
#  idx_dialer_logs_on_contact_id                       (jabvox_dialer_campaign_contact_id)
#  idx_dialer_logs_open_by_account                     (account_id,started_at_jabvox) WHERE ((status_jabvox)::text = ANY ((ARRAY['initiated'::character varying, 'calling'::character varying])::text[]))
#  idx_on_account_id_uniqueid_jabvox_8158b17c6d        (account_id,uniqueid_jabvox)
#  index_jabvox_dialer_call_logs_on_account_id         (account_id)
#  index_jabvox_dialer_call_logs_on_started_at_jabvox  (started_at_jabvox)
#  index_jabvox_dialer_call_logs_on_typification_id    (typification_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (agent_id_jabvox => users.id) ON DELETE => nullify
#  fk_rails_...  (jabvox_dialer_campaign_contact_id => jabvox_dialer_campaign_contacts.id)
#  fk_rails_...  (jabvox_dialer_campaign_id => jabvox_dialer_campaigns.id)
#  fk_rails_...  (typification_id => jabvox_typifications.id)
#
class JabvoxDialerCallLog < ApplicationRecord
  self.table_name = 'jabvox_dialer_call_logs'

  STATUSES = %w[initiated answered busy no_answer failed].freeze

  belongs_to :account
  belongs_to :jabvox_dialer_campaign
  belongs_to :jabvox_dialer_campaign_contact
  belongs_to :typification, class_name: 'JabvoxTypification', optional: true,
                            foreign_key: :typification_id, inverse_of: :dialer_call_logs

  validates :phone_jabvox, presence: true
  validates :status_jabvox, inclusion: { in: STATUSES }

  scope :ordered, -> { order(started_at_jabvox: :desc) }
end
