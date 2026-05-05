# frozen_string_literal: true

# == Schema Information
#
# Table name: jabvox_app_states
#
#  id         :bigint           not null, primary key
#  color      :string           default("#6b7280"), not null
#  is_active  :boolean          default(TRUE), not null
#  name       :string           not null
#  position   :integer          default(0), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  index_jabvox_app_states_on_account_id               (account_id)
#  index_jabvox_app_states_on_account_id_and_position  (account_id,position)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxAppState < ApplicationRecord
  belongs_to :account
  has_many :account_users, foreign_key: :jabvox_app_state_id, inverse_of: :jabvox_app_state, dependent: :nullify

  validates :name, presence: true

  scope :active, -> { where(is_active: true) }
  scope :ordered, -> { order(:position, :name) }
end
