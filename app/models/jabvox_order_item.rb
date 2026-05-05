# == Schema Information
#
# Table name: jabvox_order_items
#
#  id                :bigint           not null, primary key
#  discount_pct      :decimal(5, 2)    default(0.0), not null
#  line_total        :decimal(14, 2)   default(0.0), not null
#  name_snapshot     :string           not null
#  quantity          :decimal(10, 2)   default(1.0), not null
#  tax_pct           :decimal(5, 2)    default(0.0), not null
#  unit_price        :decimal(14, 2)   default(0.0), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  jabvox_order_id   :bigint           not null
#  jabvox_product_id :bigint
#
# Indexes
#
#  index_jabvox_order_items_on_jabvox_order_id    (jabvox_order_id)
#  index_jabvox_order_items_on_jabvox_product_id  (jabvox_product_id)
#
# Foreign Keys
#
#  fk_rails_...  (jabvox_order_id => jabvox_orders.id)
#
class JabvoxOrderItem < ApplicationRecord
  self.table_name = 'jabvox_order_items'

  belongs_to :jabvox_order
  belongs_to :jabvox_product, optional: true

  validates :name_snapshot, presence: true
  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price, numericality: { greater_than_or_equal_to: 0 }
end
