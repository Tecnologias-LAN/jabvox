# frozen_string_literal: true

# == Schema Information
#
# Table name: jabvox_dialer_states
#
#  id         :bigint           not null, primary key
#  color      :string           default("#64748b")
#  is_active  :boolean          default(TRUE), not null
#  name       :string           not null
#  position   :integer          default(0)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  index_jabvox_dialer_states_on_account_id  (account_id)
#
class JabvoxDialerState < ApplicationRecord
  belongs_to :account

  validates :name, presence: true

  scope :ordered, -> { order(:position, :name) }
  scope :active, -> { where(is_active: true) }
end
