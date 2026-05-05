# == Schema Information
#
# Table name: jabvox_orders
#
#  id              :bigint           not null, primary key
#  alegra_number   :string
#  discount_total  :decimal(14, 2)   default(0.0), not null
#  doc_type        :string           default("QUOTE"), not null
#  notes           :text
#  status          :string           default("draft"), not null
#  subtotal        :decimal(14, 2)   default(0.0), not null
#  tax_total       :decimal(14, 2)   default(0.0), not null
#  total           :decimal(14, 2)   default(0.0), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  alegra_id       :integer
#  contact_id      :bigint
#  conversation_id :bigint
#
# Indexes
#
#  index_jabvox_orders_on_account_id       (account_id)
#  index_jabvox_orders_on_contact_id       (contact_id)
#  index_jabvox_orders_on_conversation_id  (conversation_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxOrder < ApplicationRecord
  self.table_name = 'jabvox_orders'

  DOC_TYPES = %w[QUOTE SALE].freeze

  belongs_to :account
  belongs_to :contact, optional: true
  belongs_to :conversation, optional: true
  has_many :jabvox_order_items, dependent: :destroy
  accepts_nested_attributes_for :jabvox_order_items, allow_destroy: true

  validates :doc_type, inclusion: { in: DOC_TYPES }
  validates :status, presence: true
end
