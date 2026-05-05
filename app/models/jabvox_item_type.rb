# == Schema Information
#
# Table name: jabvox_item_types
#
#  id            :bigint           not null, primary key
#  active_jabvox :boolean          default(TRUE), not null
#  name_jabvox   :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#
# Indexes
#
#  index_jabvox_item_types_account_name   (account_id,name_jabvox) UNIQUE
#  index_jabvox_item_types_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxItemType < ApplicationRecord
  self.table_name = 'jabvox_item_types'

  belongs_to :account
  has_many :jabvox_products, dependent: :nullify

  validates :name_jabvox, presence: true, uniqueness: { scope: :account_id }

  scope :active, -> { where(active_jabvox: true) }
  scope :ordered, -> { order(:name_jabvox) }
end
