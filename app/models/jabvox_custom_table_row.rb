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
#  index_jabvox_custom_table_rows_on_contact_id              (contact_id)
#  index_jabvox_custom_table_rows_on_jabvox_custom_table_id  (jabvox_custom_table_id)
#  index_jabvox_custom_table_rows_on_jabvox_lead_id          (jabvox_lead_id)
#
# Foreign Keys
#
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => cascade
#  fk_rails_...  (jabvox_custom_table_id => jabvox_custom_tables.id)
#  fk_rails_...  (jabvox_lead_id => jabvox_leads.id) ON DELETE => cascade
#
class JabvoxCustomTableRow < ApplicationRecord
  belongs_to :jabvox_custom_table
  belongs_to :jabvox_lead, optional: true
  belongs_to :contact, optional: true

  validates :jabvox_custom_table_id, presence: true
  validate :requires_owner_when_linked
  validate :single_kind_allows_one_row_per_owner

  # Rows of a table linked to leads/contacts always belong to a lead or contact.
  # Standalone tables (linked_to_jabvox nil) own their rows directly, so a row
  # with neither is valid there.
  scope :standalone, -> { where(jabvox_lead_id: nil, contact_id: nil) }
  scope :for_lead, ->(lead_id) { where(jabvox_lead_id: lead_id) }

  private

  def requires_owner_when_linked
    return if jabvox_custom_table&.linked_to_jabvox.blank?
    return if jabvox_lead_id.present? || contact_id.present?

    errors.add(:base, 'Must belong to a lead or contact')
  end

  # single-kind tables keep the historical one-row-per-owner rule (the DB
  # unique index was dropped so multi tables can have many rows, so we enforce
  # single-kind uniqueness here instead).
  def single_kind_allows_one_row_per_owner
    return if jabvox_custom_table&.multi?
    return if jabvox_lead_id.blank? && contact_id.blank?

    dupes = self.class.where(jabvox_custom_table_id: jabvox_custom_table_id)
    dupes = dupes.where(jabvox_lead_id: jabvox_lead_id) if jabvox_lead_id.present?
    dupes = dupes.where(contact_id: contact_id) if contact_id.present?
    dupes = dupes.where.not(id: id) if persisted?

    errors.add(:base, 'Ya existe un registro para este propietario') if dupes.exists?
  end
end
