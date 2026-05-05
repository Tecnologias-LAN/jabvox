# == Schema Information
#
# Table name: jabvox_products
#
#  id                         :bigint           not null, primary key
#  active_jabvox              :boolean          default(TRUE), not null
#  base_price_jabvox          :decimal(12, 2)
#  description_jabvox         :text
#  integration_item_id_jabvox :integer
#  name_jabvox                :string           not null
#  price_jabvox               :decimal(12, 2)   default(0.0), not null
#  product_type_jabvox        :string           default("product"), not null
#  tax_percentage_jabvox      :decimal(5, 2)
#  total_price_jabvox         :decimal(12, 2)
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  account_id                 :bigint           not null
#  jabvox_currency_id         :bigint
#  jabvox_item_type_id        :bigint
#  jabvox_unit_of_measure_id  :bigint
#
# Indexes
#
#  index_jabvox_products_account_name                  (account_id,name_jabvox) UNIQUE
#  index_jabvox_products_on_account_id                 (account_id)
#  index_jabvox_products_on_jabvox_currency_id         (jabvox_currency_id)
#  index_jabvox_products_on_jabvox_item_type_id        (jabvox_item_type_id)
#  index_jabvox_products_on_jabvox_unit_of_measure_id  (jabvox_unit_of_measure_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (jabvox_currency_id => jabvox_currencies.id)
#  fk_rails_...  (jabvox_item_type_id => jabvox_item_types.id)
#  fk_rails_...  (jabvox_unit_of_measure_id => jabvox_units_of_measure.id)
#
class JabvoxProduct < ApplicationRecord
  self.table_name = 'jabvox_products'

  PRODUCT_TYPES = %w[product service].freeze

  belongs_to :account
  belongs_to :jabvox_currency, optional: true
  belongs_to :jabvox_item_type, optional: true
  belongs_to :jabvox_unit_of_measure, optional: true

  validates :name_jabvox, presence: true, uniqueness: { scope: :account_id }
  validates :price_jabvox, numericality: { greater_than_or_equal_to: 0 }
  validates :product_type_jabvox, inclusion: { in: PRODUCT_TYPES }

  scope :active, -> { where(active_jabvox: true) }
  scope :ordered, -> { order(:name_jabvox) }
end
