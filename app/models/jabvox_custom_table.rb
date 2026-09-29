# == Schema Information
#
# Table name: jabvox_custom_tables
#
#  id                 :bigint           not null, primary key
#  description_jabvox :text
#  kind_jabvox        :string           default("single"), not null
#  linked_to_jabvox   :string
#  name_jabvox        :string           not null
#  position_jabvox    :integer          default(0), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  created_by_id      :bigint
#
# Indexes
#
#  idx_jabvox_custom_tables_linked_to                        (account_id,linked_to_jabvox) UNIQUE WHERE (linked_to_jabvox IS NOT NULL)
#  index_jabvox_custom_tables_on_account_id                  (account_id)
#  index_jabvox_custom_tables_on_account_id_and_name_jabvox  (account_id,name_jabvox) UNIQUE
#  index_jabvox_custom_tables_on_created_by_id               (created_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#
class JabvoxCustomTable < ApplicationRecord
  # single = one row per lead (the Leads table stores values inline instead);
  # multi  = many rows per lead (Asesorías, Casos…), each an independent record.
  KINDS = %w[single multi].freeze

  belongs_to :account
  has_many :jabvox_custom_columns, -> { order(:position_jabvox) }, dependent: :destroy
  has_many :jabvox_custom_table_rows, dependent: :destroy

  validates :name_jabvox, presence: true, uniqueness: { scope: :account_id }
  validates :kind_jabvox, inclusion: { in: KINDS }

  scope :ordered, -> { order(:position_jabvox, :name_jabvox) }
  # The single system table for inline lead fields.
  scope :for_contacts, -> { where(linked_to_jabvox: 'contacts', kind_jabvox: 'single') }
  scope :standalone, -> { where(linked_to_jabvox: nil) }
  # Tablas multi-fila (Asesorías, Casos…). NO están vinculadas a 'contacts' (eso
  # slot is reserved for the single system table and is unique per account);
  # instead each of their ROWS carries a jabvox_lead_id, so a lead's detail can
  # show them. This keeps them clear of the single-leads-table unique index.
  scope :multi_for_contacts, -> { where(kind_jabvox: 'multi') }

  def multi?
    kind_jabvox == 'multi'
  end

  # The locked system table (inline lead fields) — never a multi table.
  def system_leads_table?
    linked_to_jabvox == 'contacts' && !multi?
  end
end
