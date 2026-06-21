# == Schema Information
#
# Table name: jabvox_custom_tables
#
#  id                 :bigint           not null, primary key
#  description_jabvox :text
#  linked_to_jabvox   :string
#  name_jabvox        :string           not null
#  position_jabvox    :integer          default(0), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#
# Indexes
#
#  idx_jabvox_custom_tables_linked_to                        (account_id,linked_to_jabvox) UNIQUE WHERE (linked_to_jabvox IS NOT NULL)
#  index_jabvox_custom_tables_on_account_id                  (account_id)
#  index_jabvox_custom_tables_on_account_id_and_name_jabvox  (account_id,name_jabvox) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxCustomTable < ApplicationRecord
  belongs_to :account
  has_many :jabvox_custom_columns, -> { order(:position_jabvox) }, dependent: :destroy
  has_many :jabvox_custom_table_rows, dependent: :destroy

  validates :name_jabvox, presence: true, uniqueness: { scope: :account_id }

  scope :ordered, -> { order(:position_jabvox, :name_jabvox) }
  scope :for_leads, -> { where(linked_to_jabvox: 'leads') }
  scope :standalone, -> { where(linked_to_jabvox: nil) }
end
