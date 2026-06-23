# A column on a task board.
# == Schema Information
#
# Table name: jabvox_task_stages
#
#  id              :bigint           not null, primary key
#  color_jabvox    :string           default("#6b7280"), not null
#  name_jabvox     :string           not null
#  position_jabvox :integer          default(0), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  board_id        :bigint           not null
#
# Indexes
#
#  index_jabvox_task_stages_on_account_id                    (account_id)
#  index_jabvox_task_stages_on_board_id                      (board_id)
#  index_jabvox_task_stages_on_board_id_and_position_jabvox  (board_id,position_jabvox)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (board_id => jabvox_task_boards.id)
#
class JabvoxTaskStage < ApplicationRecord
  self.table_name = 'jabvox_task_stages'

  belongs_to :account
  belongs_to :board, class_name: 'JabvoxTaskBoard'

  has_many :tasks, class_name: 'JabvoxTask', foreign_key: :stage_id,
                   dependent: :nullify, inverse_of: :stage
  has_many :automations, class_name: 'JabvoxTaskStageAutomation', foreign_key: :stage_id,
                         dependent: :destroy, inverse_of: :stage

  validates :name_jabvox, presence: true

  scope :ordered, -> { order(:position_jabvox) }
end
