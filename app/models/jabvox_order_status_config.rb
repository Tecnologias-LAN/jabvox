# == Schema Information
#
# Table name: jabvox_order_status_configs
#
#  id                :bigint           not null, primary key
#  color_jabvox      :string           default("#6B7280"), not null
#  key_jabvox        :string           not null
#  label_jabvox      :string           not null
#  sort_order_jabvox :integer          default(0), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#
# Indexes
#
#  index_jabvox_order_status_account_key            (account_id,key_jabvox) UNIQUE
#  index_jabvox_order_status_configs_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxOrderStatusConfig < ApplicationRecord
  self.table_name = 'jabvox_order_status_configs'

  belongs_to :account

  validates :key_jabvox, presence: true, uniqueness: { scope: :account_id }
  validates :label_jabvox, presence: true
  validates :sort_order_jabvox, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :ordered, -> { order(:sort_order_jabvox, :created_at) }
end
