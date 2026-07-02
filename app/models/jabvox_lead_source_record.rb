# Maps one external row (external_id) to the lead created/updated from it. This is
# the persistent link between the external database id and the app's lead id, used
# to decide on each sync whether to create a new lead or update the existing one.
# == Schema Information
#
# Table name: jabvox_lead_source_records
#
#  id                    :bigint           not null, primary key
#  external_id_jabvox    :string           not null
#  last_synced_at_jabvox :datetime
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#  jabvox_lead_id        :bigint           not null
#  lead_source_id        :bigint           not null
#
# Indexes
#
#  index_jabvox_lead_source_records_on_account_id              (account_id)
#  index_jabvox_lead_source_records_on_jabvox_lead_id          (jabvox_lead_id)
#  index_jabvox_lead_source_records_on_lead_source_id          (lead_source_id)
#  index_jabvox_lead_source_records_on_source_and_external_id  (lead_source_id,external_id_jabvox) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (jabvox_lead_id => jabvox_leads.id)
#  fk_rails_...  (lead_source_id => jabvox_lead_sources.id)
#
class JabvoxLeadSourceRecord < ApplicationRecord
  self.table_name = 'jabvox_lead_source_records'

  belongs_to :lead_source, class_name: 'JabvoxLeadSource'
  belongs_to :account
  belongs_to :jabvox_lead, class_name: 'JabvoxLead'

  validates :external_id_jabvox, presence: true,
                                 uniqueness: { scope: :lead_source_id }
end
