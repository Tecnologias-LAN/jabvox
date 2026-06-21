# == Schema Information
#
# Table name: jabvox_management_states
#
#  id               :bigint           not null, primary key
#  color_jabvox     :string           default("#6366f1"), not null
#  is_active_jabvox :boolean          default(TRUE), not null
#  name_jabvox      :string           default(""), not null
#  note_mode        :string           default("optional"), not null
#  position_jabvox  :integer          default(0), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#
# Indexes
#
#  index_jabvox_management_states_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxManagementState < ApplicationRecord
  self.table_name = 'jabvox_management_states'

  NOTE_MODES = %w[required optional hidden].freeze

  belongs_to :account
  has_many :questions, -> { order(:position) }, class_name: 'JabvoxManagementQuestion',
                                                foreign_key: :jabvox_management_state_id, dependent: :destroy, inverse_of: :management_state

  accepts_nested_attributes_for :questions, allow_destroy: true

  validates :name_jabvox, presence: true, uniqueness: { scope: :account_id }
  validates :position_jabvox, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :note_mode, inclusion: { in: NOTE_MODES }

  scope :active, -> { where(is_active_jabvox: true) }
  scope :ordered, -> { order(:position_jabvox, :name_jabvox) }
end
