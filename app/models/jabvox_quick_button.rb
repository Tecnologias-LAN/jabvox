# == Schema Information
#
# Table name: jabvox_quick_buttons
#
#  id              :bigint           not null, primary key
#  active_jabvox   :boolean          default(TRUE), not null
#  color_jabvox    :string           default("#6b7280")
#  name_jabvox     :string           not null
#  position_jabvox :integer          default(0), not null
#  url_jabvox      :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#
# Indexes
#
#  index_jabvox_quick_buttons_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxQuickButton < ApplicationRecord
  belongs_to :account

  validates :name_jabvox, presence: true
  validates :url_jabvox, presence: true

  scope :active, -> { where(active_jabvox: true) }
  scope :ordered, -> { order(:position_jabvox, :name_jabvox) }
end
