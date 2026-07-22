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
#  created_by_id   :bigint
#
# Indexes
#
#  index_jabvox_task_stages_on_account_id                    (account_id)
#  index_jabvox_task_stages_on_board_id                      (board_id)
#  index_jabvox_task_stages_on_board_id_and_position_jabvox  (board_id,position_jabvox)
#  index_jabvox_task_stages_on_created_by_id                 (created_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (board_id => jabvox_task_boards.id)
#  fk_rails_...  (created_by_id => users.id)
#
class JabvoxTaskStage < ApplicationRecord
  self.table_name = 'jabvox_task_stages'

  belongs_to :account
  belongs_to :board, class_name: 'JabvoxTaskBoard'

  has_many :tasks, class_name: 'JabvoxTask', foreign_key: :stage_id,
                   dependent: :nullify, inverse_of: :stage
  has_many :automations, class_name: 'JabvoxTaskStageAutomation', foreign_key: :stage_id,
                         dependent: :destroy, inverse_of: :stage
  # Automations on other stages that move tasks INTO this stage lose their
  # target instead of blocking the deletion.
  has_many :incoming_automations, class_name: 'JabvoxTaskStageAutomation', foreign_key: :target_stage_id,
                                  dependent: :nullify, inverse_of: false

  validates :name_jabvox, presence: true

  scope :ordered, -> { order(:position_jabvox) }
end
