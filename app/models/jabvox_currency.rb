# == Schema Information
#
# Table name: jabvox_currencies
#
#  id            :bigint           not null, primary key
#  active_jabvox :boolean          default(TRUE), not null
#  name_jabvox   :string           not null
#  symbol_jabvox :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#
# Indexes
#
#  index_jabvox_currencies_account_symbol  (account_id,symbol_jabvox) UNIQUE
#  index_jabvox_currencies_on_account_id   (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxCurrency < ApplicationRecord
  self.table_name = 'jabvox_currencies'

  belongs_to :account
  has_many :jabvox_products, dependent: :nullify

  validates :symbol_jabvox, presence: true, uniqueness: { scope: :account_id }
  validates :name_jabvox, presence: true

  scope :active, -> { where(active_jabvox: true) }
  scope :ordered, -> { order(:symbol_jabvox) }
end
