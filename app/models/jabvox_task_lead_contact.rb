# Info-only contact person captured for a lead inside the Tasks module (e.g. "Miguel, IT,
# email, phone"). This is reference data shown in the right-hand panel — it is NOT a real
# Contact and never creates leads or triggers calls.
# == Schema Information
#
# Table name: jabvox_task_lead_contacts
#
#  id                 :bigint           not null, primary key
#  description_jabvox :text
#  email_jabvox       :string           default(""), not null
#  name_jabvox        :string           not null
#  phone_jabvox       :string           default(""), not null
#  position_jabvox    :integer          default(0), not null
#  role_jabvox        :string           default(""), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  created_by_id      :bigint
#  jabvox_lead_id     :bigint           not null
#
# Indexes
#
#  idx_on_account_id_jabvox_lead_id_dd0363c234        (account_id,jabvox_lead_id)
#  index_jabvox_task_lead_contacts_on_account_id      (account_id)
#  index_jabvox_task_lead_contacts_on_created_by_id   (created_by_id)
#  index_jabvox_task_lead_contacts_on_jabvox_lead_id  (jabvox_lead_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (jabvox_lead_id => jabvox_leads.id)
#
class JabvoxTaskLeadContact < ApplicationRecord
  self.table_name = 'jabvox_task_lead_contacts'

  belongs_to :account
  belongs_to :jabvox_lead, class_name: 'JabvoxLead'
  belongs_to :created_by, class_name: 'User', optional: true

  validates :name_jabvox, presence: true

  scope :ordered, -> { order(:position_jabvox, :name_jabvox) }
end
