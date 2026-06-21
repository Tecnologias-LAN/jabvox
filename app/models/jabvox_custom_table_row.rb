# == Schema Information
#
# Table name: jabvox_custom_table_rows
#
#  id                     :bigint           not null, primary key
#  data_jabvox            :jsonb            not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  contact_id             :bigint
#  jabvox_custom_table_id :bigint           not null
#  jabvox_lead_id         :bigint
#
# Indexes
#
#  idx_custom_table_rows_table_contact                       (jabvox_custom_table_id,contact_id) UNIQUE WHERE (contact_id IS NOT NULL)
#  idx_custom_table_rows_table_lead                          (jabvox_custom_table_id,jabvox_lead_id) UNIQUE WHERE (jabvox_lead_id IS NOT NULL)
#  index_jabvox_custom_table_rows_on_contact_id              (contact_id)
#  index_jabvox_custom_table_rows_on_jabvox_custom_table_id  (jabvox_custom_table_id)
#  index_jabvox_custom_table_rows_on_jabvox_lead_id          (jabvox_lead_id)
#
# Foreign Keys
#
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (jabvox_custom_table_id => jabvox_custom_tables.id)
#  fk_rails_...  (jabvox_lead_id => jabvox_leads.id)
#
class JabvoxCustomTableRow < ApplicationRecord
  belongs_to :jabvox_custom_table
  belongs_to :jabvox_lead, optional: true
  belongs_to :contact, optional: true

  validates :jabvox_custom_table_id, presence: true
  validate :requires_lead_or_contact

  private

  def requires_lead_or_contact
    errors.add(:base, 'Must belong to a lead or contact') if jabvox_lead_id.nil? && contact_id.nil?
  end
end
