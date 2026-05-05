# == Schema Information
#
# Table name: jabvox_discounts
#
#  id                 :bigint           not null, primary key
#  active_jabvox      :boolean          default(TRUE), not null
#  description_jabvox :text
#  name_jabvox        :string           not null
#  percentage_jabvox  :decimal(5, 2)    default(0.0), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#
# Indexes
#
#  index_jabvox_discounts_account_name   (account_id,name_jabvox) UNIQUE
#  index_jabvox_discounts_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxDiscount < ApplicationRecord
  self.table_name = 'jabvox_discounts'

  belongs_to :account

  validates :name_jabvox, presence: true, uniqueness: { scope: :account_id }
  validates :percentage_jabvox, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  scope :active, -> { where(active_jabvox: true) }
  scope :ordered, -> { order(:name_jabvox) }
end
