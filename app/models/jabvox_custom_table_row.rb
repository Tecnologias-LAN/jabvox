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
#
# Indexes
#
#  index_jabvox_custom_table_rows_on_contact_id              (contact_id)
#  index_jabvox_custom_table_rows_on_jabvox_custom_table_id  (jabvox_custom_table_id)
#
# Foreign Keys
#
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => cascade
#  fk_rails_...  (jabvox_custom_table_id => jabvox_custom_tables.id)
#
class JabvoxCustomTableRow < ApplicationRecord
  belongs_to :jabvox_custom_table
  belongs_to :jabvox_lead, optional: true
  belongs_to :contact, optional: true

  validates :jabvox_custom_table_id, presence: true
  validate :requires_owner_when_linked
  validate :single_kind_allows_one_row_per_owner

  # Las filas de una tabla ligada a contactos siempre pertenecen a un contacto. Las tablas
  # sueltas (linked_to_jabvox nil) son dueñas de sus filas, así que ahí una fila sin
  # propietario es válida.
  scope :standalone, -> { where(contact_id: nil) }
  scope :for_contact, ->(contact_id) { where(contact_id: contact_id) }

  private

  def requires_owner_when_linked
    return if jabvox_custom_table&.linked_to_jabvox.blank?
    return if contact_id.present?

    errors.add(:base, 'Debe pertenecer a un contacto')
  end

  # single-kind tables keep the historical one-row-per-owner rule (the DB
  # unique index was dropped so multi tables can have many rows, so we enforce
  # single-kind uniqueness here instead).
  def single_kind_allows_one_row_per_owner
    return if jabvox_custom_table&.multi?
    return if contact_id.blank?

    dupes = self.class.where(jabvox_custom_table_id: jabvox_custom_table_id, contact_id: contact_id)
    dupes = dupes.where.not(id: id) if persisted?

    errors.add(:base, 'Ya existe un registro para este propietario') if dupes.exists?
  end
end
