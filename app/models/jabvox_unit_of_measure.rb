# == Schema Information
#
# Table name: jabvox_units_of_measure
#
#  id                  :bigint           not null, primary key
#  abbreviation_jabvox :string
#  active_jabvox       :boolean          default(TRUE), not null
#  name_jabvox         :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#
# Indexes
#
#  index_jabvox_units_account_name              (account_id,name_jabvox) UNIQUE
#  index_jabvox_units_of_measure_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxUnitOfMeasure < ApplicationRecord
  self.table_name = 'jabvox_units_of_measure'

  belongs_to :account
  has_many :jabvox_products, dependent: :nullify

  validates :name_jabvox, presence: true, uniqueness: { scope: :account_id }

  scope :active, -> { where(active_jabvox: true) }
  scope :ordered, -> { order(:name_jabvox) }
end
